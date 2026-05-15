import { mkdir, rm, writeFile } from 'node:fs/promises';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const DEFAULT_VERSION_ID = '1.21.11';
const DEFAULT_CONCURRENCY = 24;
const VERSION_MANIFEST_URL = 'https://piston-meta.mojang.com/mc/game/version_manifest_v2.json';
const ASSET_BASE_URL = 'https://resources.download.minecraft.net';

function parseArgs(argv) {
  const options = {
    version: DEFAULT_VERSION_ID,
    concurrency: DEFAULT_CONCURRENCY,
  };

  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (argument === '--version') {
      const nextValue = argv[index + 1] || '';
      if (!nextValue) {
        throw new Error('Missing value for --version');
      }
      options.version = nextValue.trim();
      index += 1;
      continue;
    }

    if (argument === '--concurrency') {
      const nextValue = Number(argv[index + 1] || '');
      if (!Number.isFinite(nextValue) || nextValue <= 0) {
        throw new Error('Invalid value for --concurrency');
      }
      options.concurrency = Math.max(1, Math.floor(nextValue));
      index += 1;
      continue;
    }
  }

  return options;
}

async function fetchJson(url) {
  const response = await fetch(url);
  if (!response.ok) {
    throw new Error(`Request failed for ${url}: ${response.status} ${response.statusText}`);
  }
  return response.json();
}

async function fetchBuffer(url) {
  const response = await fetch(url);
  if (!response.ok) {
    throw new Error(`Request failed for ${url}: ${response.status} ${response.statusText}`);
  }
  const arrayBuffer = await response.arrayBuffer();
  return Buffer.from(arrayBuffer);
}

function normalizeMinecraftId(value) {
  const normalizedValue = String(value || '').trim();
  if (!normalizedValue) {
    return '';
  }

  if (normalizedValue.includes(':')) {
    const [namespace, path] = normalizedValue.split(':', 2);
    if (namespace !== 'minecraft') {
      return '';
    }
    return path.trim();
  }

  return normalizedValue;
}

function normalizeSoundFilePath(value) {
  const normalizedValue = normalizeMinecraftId(value);
  if (!normalizedValue) {
    return '';
  }

  return normalizedValue.toLowerCase().endsWith('.ogg') ? normalizedValue : `${normalizedValue}.ogg`;
}

function formatWord(word) {
  const normalizedWord = String(word || '').trim();
  if (!normalizedWord) {
    return '';
  }

  if (/^\d+$/u.test(normalizedWord)) {
    return normalizedWord;
  }

  return normalizedWord.charAt(0).toUpperCase() + normalizedWord.slice(1);
}

function formatEventName(eventPath) {
  return eventPath
    .split(/[./_]+/u)
    .map((word) => formatWord(word))
    .filter(Boolean)
    .join(' ');
}

function parseOggDurationSeconds(buffer) {
  let offset = 0;
  let sampleRate = 0;
  let lastGranulePosition = 0n;

  while (offset + 27 <= buffer.length) {
    if (buffer.toString('ascii', offset, offset + 4) !== 'OggS') {
      break;
    }

    const pageSegments = buffer[offset + 26];
    const segmentTableOffset = offset + 27;
    if (segmentTableOffset + pageSegments > buffer.length) {
      break;
    }

    let pageSize = 0;
    for (let index = 0; index < pageSegments; index += 1) {
      pageSize += buffer[segmentTableOffset + index];
    }

    const pageDataOffset = segmentTableOffset + pageSegments;
    if (pageDataOffset + pageSize > buffer.length) {
      break;
    }

    if (sampleRate === 0 && pageSize >= 16 && buffer[pageDataOffset] === 0x01 && buffer.toString('ascii', pageDataOffset + 1, pageDataOffset + 7) === 'vorbis') {
      sampleRate = buffer.readUInt32LE(pageDataOffset + 12);
    }

    const granulePosition = buffer.readBigUInt64LE(offset + 6);
    if (granulePosition > 0n) {
      lastGranulePosition = granulePosition;
    }

    offset = pageDataOffset + pageSize;
  }

  if (sampleRate <= 0 || lastGranulePosition <= 0n) {
    return 0;
  }

  return Number(lastGranulePosition) / sampleRate;
}

function roundDurationSeconds(value) {
  return Math.round(value * 1000) / 1000;
}

function toDurationTicks(value) {
  return Math.max(0, Math.round(value * 20));
}

function buildAssetDownloadUrl(hash) {
  return `${ASSET_BASE_URL}/${hash.slice(0, 2)}/${hash}`;
}

function normalizeSoundEntries(eventValue) {
  if (!eventValue || typeof eventValue !== 'object') {
    return [];
  }

  return Array.isArray(eventValue.sounds) ? eventValue.sounds : [];
}

function resolveEventSoundFiles(eventPath, soundsConfig, memo, stack = new Set()) {
  const normalizedEventPath = normalizeMinecraftId(eventPath);
  if (!normalizedEventPath) {
    return [];
  }

  const cachedResult = memo.get(normalizedEventPath);
  if (cachedResult) {
    return cachedResult;
  }

  if (stack.has(normalizedEventPath)) {
    return [];
  }

  const eventValue = soundsConfig[normalizedEventPath];
  if (!eventValue || typeof eventValue !== 'object') {
    memo.set(normalizedEventPath, []);
    return [];
  }

  stack.add(normalizedEventPath);
  const files = [];
  const seenFiles = new Set();
  for (const soundEntry of normalizeSoundEntries(eventValue)) {
    if (typeof soundEntry === 'string') {
      const soundFilePath = normalizeSoundFilePath(soundEntry);
      if (soundFilePath && !seenFiles.has(soundFilePath)) {
        seenFiles.add(soundFilePath);
        files.push(soundFilePath);
      }
      continue;
    }

    if (!soundEntry || typeof soundEntry !== 'object') {
      continue;
    }

    const soundName = String(soundEntry.name || '').trim();
    const soundType = String(soundEntry.type || 'file').trim().toLowerCase();
    if (!soundName) {
      continue;
    }

    if (soundType === 'event') {
      for (const resolvedFile of resolveEventSoundFiles(soundName, soundsConfig, memo, stack)) {
        if (!seenFiles.has(resolvedFile)) {
          seenFiles.add(resolvedFile);
          files.push(resolvedFile);
        }
      }
      continue;
    }

    const soundFilePath = normalizeSoundFilePath(soundName);
    if (soundFilePath && !seenFiles.has(soundFilePath)) {
      seenFiles.add(soundFilePath);
      files.push(soundFilePath);
    }
  }

  stack.delete(normalizedEventPath);
  memo.set(normalizedEventPath, files);
  return files;
}

async function runPool(items, worker, concurrency) {
  const queue = [...items];
  const workers = Array.from({ length: Math.min(concurrency, queue.length) }, async () => {
    while (queue.length > 0) {
      const item = queue.shift();
      if (item === undefined) {
        return;
      }
      await worker(item);
    }
  });

  await Promise.all(workers);
}

async function main() {
  const options = parseArgs(process.argv.slice(2));
  const scriptPath = fileURLToPath(import.meta.url);
  const scriptDirectory = dirname(scriptPath);
  const outputJsonPath = join(scriptDirectory, 'audio.json');
  const outputAudioDirectory = join(scriptDirectory, 'audio');

  console.log(`Loading version metadata for Minecraft ${options.version}...`);
  const manifest = await fetchJson(VERSION_MANIFEST_URL);
  const versionEntry = Array.isArray(manifest.versions)
    ? manifest.versions.find((entry) => String(entry?.id || '').trim() === options.version)
    : null;
  if (!versionEntry?.url) {
    throw new Error(`Version ${options.version} was not found in the Mojang version manifest.`);
  }

  const versionMeta = await fetchJson(versionEntry.url);
  if (!versionMeta?.assetIndex?.url) {
    throw new Error(`Version ${options.version} did not expose an asset index URL.`);
  }

  console.log(`Loading asset index ${versionMeta.assetIndex.id || versionMeta.assets || ''}...`);
  const assetIndex = await fetchJson(versionMeta.assetIndex.url);
  const assetObjects = assetIndex?.objects && typeof assetIndex.objects === 'object' ? assetIndex.objects : {};
  const soundsJsonObject = assetObjects['minecraft/sounds.json'];
  if (!soundsJsonObject?.hash) {
    throw new Error(`minecraft/sounds.json was not found in the asset index for ${options.version}.`);
  }

  const soundsJsonBuffer = await fetchBuffer(buildAssetDownloadUrl(soundsJsonObject.hash));
  const soundsConfig = JSON.parse(soundsJsonBuffer.toString('utf8'));
  const memo = new Map();
  const eventEntries = [];
  const requiredSoundFiles = new Set();

  console.log('Resolving playable sound events...');
  for (const rawEventPath of Object.keys(soundsConfig).sort((left, right) => left.localeCompare(right))) {
    const resolvedSoundFiles = resolveEventSoundFiles(rawEventPath, soundsConfig, memo);
    if (resolvedSoundFiles.length === 0) {
      continue;
    }

    for (const soundFilePath of resolvedSoundFiles) {
      requiredSoundFiles.add(soundFilePath);
    }

    eventEntries.push({
      key: `minecraft:${rawEventPath}`,
      eventPath: rawEventPath,
      previewPath: resolvedSoundFiles[0],
      soundFiles: resolvedSoundFiles,
    });
  }

  console.log(`Resolved ${eventEntries.length} playable sound events using ${requiredSoundFiles.size} unique sound files.`);

  await rm(outputAudioDirectory, { recursive: true, force: true });
  await mkdir(outputAudioDirectory, { recursive: true });

  const durationBySoundFile = new Map();
  let downloadedCount = 0;
  const soundFiles = [...requiredSoundFiles].sort((left, right) => left.localeCompare(right));

  console.log(`Downloading ${soundFiles.length} sound files into ${outputAudioDirectory}...`);
  await runPool(soundFiles, async (soundFilePath) => {
    const assetKey = `minecraft/sounds/${soundFilePath}`;
    const assetObject = assetObjects[assetKey];
    if (!assetObject?.hash) {
      throw new Error(`Missing asset index entry for ${assetKey}.`);
    }

    const fileBuffer = await fetchBuffer(buildAssetDownloadUrl(assetObject.hash));
    const destinationPath = join(outputAudioDirectory, soundFilePath);
    await mkdir(dirname(destinationPath), { recursive: true });
    await writeFile(destinationPath, fileBuffer);
    durationBySoundFile.set(soundFilePath, roundDurationSeconds(parseOggDurationSeconds(fileBuffer)));

    downloadedCount += 1;
    if (downloadedCount % 100 === 0 || downloadedCount === soundFiles.length) {
      console.log(`Downloaded ${downloadedCount}/${soundFiles.length} sound files...`);
    }
  }, options.concurrency);

  const audioDefinitions = {};
  for (const entry of eventEntries) {
    const maxDurationSeconds = entry.soundFiles.reduce((maxDuration, soundFilePath) => {
      const durationSeconds = durationBySoundFile.get(soundFilePath) || 0;
      return durationSeconds > maxDuration ? durationSeconds : maxDuration;
    }, 0);
    const eventId = entry.key;
    audioDefinitions[eventId] = {
      id: eventId,
      name: formatEventName(entry.eventPath),
      subtitle: eventId,
      audio: entry.previewPath,
      durationSeconds: roundDurationSeconds(maxDurationSeconds),
      durationTicks: toDurationTicks(maxDurationSeconds),
      hideImage: true,
    };
  }

  await writeFile(outputJsonPath, `${JSON.stringify(audioDefinitions, null, 4)}\n`, 'utf8');
  console.log(`Wrote ${Object.keys(audioDefinitions).length} audio definitions to ${outputJsonPath}.`);
}

main().catch((error) => {
  console.error(error instanceof Error ? error.message : error);
  process.exitCode = 1;
});