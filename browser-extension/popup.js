const PUSH_PORT = 26982;

const el = {
  videoTitle: document.getElementById('videoTitle'),
  videoMeta: document.getElementById('videoMeta'),
  deviceList: document.getElementById('deviceList'),
  ipInput: document.getElementById('ipInput'),
  addBtn: document.getElementById('addBtn'),
  status: document.getElementById('status'),
};

let videoInfo = null;

function setStatus(text) {
  el.status.textContent = text;
}

async function getVideoInfo() {
  const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
  if (!tab?.id) return null;
  try {
    return await chrome.tabs.sendMessage(tab.id, { type: 'getVideoInfo' });
  } catch {
    return null;
  }
}

async function pingDevice(ip) {
  try {
    const resp = await fetch(`http://${ip}:${PUSH_PORT}/ping`);
    if (!resp.ok) return null;
    return await resp.json();
  } catch {
    return null;
  }
}

async function pushTo(device) {
  if (!videoInfo || (!videoInfo.bvid && !videoInfo.epId)) {
    setStatus('未识别到可推送的视频');
    return;
  }
  const message = {
    t: 'push',
    id: crypto.randomUUID(),
    v: 1,
    app: 'com.shaoy.piliplus',
    from: '电脑浏览器',
    payload: {
      type: videoInfo.type,
      bvid: videoInfo.bvid,
      aid: videoInfo.aid,
      cid: videoInfo.cid,
      epId: videoInfo.epId,
      seasonId: videoInfo.seasonId,
      title: videoInfo.title || '',
      cover: videoInfo.cover || '',
      positionSec: videoInfo.position || 0,
    },
  };
  try {
    const resp = await fetch(`http://${device.ip}:${PUSH_PORT}/push`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(message),
    });
    setStatus(resp.ok ? `已推送到 ${device.name || device.ip}` : `推送失败 (HTTP ${resp.status})`);
  } catch {
    setStatus('推送失败，请检查设备 IP 与网络');
  }
}

async function loadDevices() {
  const { devices = [] } = await chrome.storage.local.get('devices');
  return devices;
}

async function saveDevices(devices) {
  await chrome.storage.local.set({ devices });
}

async function renderDevices() {
  const devices = await loadDevices();
  el.deviceList.textContent = '';
  if (devices.length === 0) {
    const empty = document.createElement('div');
    empty.className = 'empty';
    empty.textContent = '还没有设备，请在下方添加手机/平板的 IP';
    el.deviceList.appendChild(empty);
    return;
  }
  for (const device of devices) {
    const row = document.createElement('div');
    row.className = 'device-row';

    const label = document.createElement('div');
    label.className = 'device-label';
    label.textContent = device.name ? `${device.name} (${device.ip})` : device.ip;

    const pushBtn = document.createElement('button');
    pushBtn.textContent = '推送';
    pushBtn.disabled = !videoInfo || (!videoInfo.bvid && !videoInfo.epId);
    pushBtn.onclick = () => pushTo(device);

    const delBtn = document.createElement('button');
    delBtn.className = 'del';
    delBtn.textContent = '删除';
    delBtn.onclick = async () => {
      await saveDevices(devices.filter((d) => d.ip !== device.ip));
      await renderDevices();
    };

    row.appendChild(label);
    row.appendChild(pushBtn);
    row.appendChild(delBtn);
    el.deviceList.appendChild(row);
  }
}

async function refreshVideo() {
  videoInfo = await getVideoInfo();
  if (videoInfo && (videoInfo.bvid || videoInfo.epId)) {
    el.videoTitle.textContent = videoInfo.title || '未知视频';
    const type = videoInfo.type === 'pgc' ? '番剧/影视' : '视频';
    const id = videoInfo.bvid || `ep${videoInfo.epId}`;
    el.videoMeta.textContent = `${type} · ${id}${videoInfo.position > 0 ? ` · 进度 ${videoInfo.position}s` : ''}`;
  } else {
    el.videoTitle.textContent = '未识别到 B 站视频页';
    el.videoMeta.textContent = '';
  }
  await renderDevices();
}

el.addBtn.onclick = async () => {
  const ip = el.ipInput.value.trim();
  if (!ip) return;
  const result = await pingDevice(ip);
  if (!result?.ok) {
    setStatus(`无法连接 ${ip}，请确认设备已安装新版 PiliPlus 且在同一网络`);
    return;
  }
  const devices = await loadDevices();
  const exists = devices.some((d) => d.ip === ip);
  const name = result.receiving ? result.name : `${result.name}（未开启接收）`;
  if (!exists) {
    devices.push({ ip, name: result.name });
    await saveDevices(devices);
  } else {
    devices[devices.findIndex((d) => d.ip === ip)].name = result.name;
    await saveDevices(devices);
  }
  setStatus(`已添加 ${name}`);
  el.ipInput.value = '';
  await renderDevices();
};

refreshVideo();
