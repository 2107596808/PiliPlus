// v2 协议：单端口 26982，HTTP 推送 + /pair 配对
const PUSH_PORT = 26982;
const PROTOCOL_VERSION = 2;
const APP_ID = 'com.shaoy.piliplus';
const TOKEN_HEADER = 'x-piliplus-token';

async function getToken(ip) {
  const { tokens = {} } = await chrome.storage.local.get('tokens');
  return tokens[ip] || null;
}

async function setToken(ip, token) {
  const { tokens = {} } = await chrome.storage.local.get('tokens');
  if (token) {
    tokens[ip] = token;
  } else {
    delete tokens[ip];
  }
  await chrome.storage.local.set({ tokens });
}

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

function buildPayload() {
  const isLink = !videoInfo.bvid && !videoInfo.epId && videoInfo.url;
  if (isLink) {
    return { kind: 'link', url: videoInfo.url, title: videoInfo.title || '' };
  }
  return {
    kind: 'video',
    type: videoInfo.type,
    bvid: videoInfo.bvid,
    aid: videoInfo.aid,
    cid: videoInfo.cid,
    epId: videoInfo.epId,
    seasonId: videoInfo.seasonId,
    title: videoInfo.title || '',
    cover: videoInfo.cover || '',
    positionSec: videoInfo.position || 0,
  };
}

async function pushTo(device) {
  if (!videoInfo) {
    setStatus('未识别到可推送的内容');
    return;
  }
  const payload = buildPayload();
  if (payload.kind === 'video' && !payload.cid && !payload.epId) {
    setStatus('未识别到可推送的视频');
    return;
  }
  const token = await getToken(device.ip);
  const message = {
    t: 'push',
    id: crypto.randomUUID(),
    v: PROTOCOL_VERSION,
    app: APP_ID,
    from: '电脑浏览器',
    payload,
    token,
  };
  try {
    const headers = { 'Content-Type': 'application/json' };
    if (token) headers[TOKEN_HEADER] = token;
    const resp = await fetch(`http://${device.ip}:${PUSH_PORT}/push`, {
      method: 'POST',
      headers,
      body: JSON.stringify(message),
    });
    if (resp.status === 403) {
      await setToken(device.ip, null);
      setStatus('配对已失效，请重新配对');
      return;
    }
    setStatus(resp.ok ? `已推送到 ${device.name || device.ip}` : `推送失败 (HTTP ${resp.status})`);
  } catch {
    setStatus('推送失败，请检查设备 IP 与网络');
  }
}

// 配对：向设备索取配对码，用户输入后换取令牌
async function pairDevice(device, code) {
  const base = `http://${device.ip}:${PUSH_PORT}/pair`;
  const body = {
    t: code ? 'pair_submit' : 'pair_request',
    id: crypto.randomUUID(),
    v: PROTOCOL_VERSION,
    app: APP_ID,
    from: '电脑浏览器',
    code: code || undefined,
  };
  const resp = await fetch(base, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  });
  if (!resp.ok) return null;
  return await resp.json();
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
    const token = await getToken(device.ip);
    const row = document.createElement('div');
    row.className = 'device-row';

    const label = document.createElement('div');
    label.className = 'device-label';
    label.textContent = device.name ? `${device.name} (${device.ip})` : device.ip;

    const pushBtn = document.createElement('button');
    pushBtn.textContent = '推送';
    pushBtn.disabled = !videoInfo;
    pushBtn.onclick = () => pushTo(device);

    const pairBtn = document.createElement('button');
    pairBtn.textContent = token ? '已配对' : '配对';
    pairBtn.disabled = !!token;
    pairBtn.onclick = async () => {
      const requested = await pairDevice(device);
      if (!requested?.ok) {
        setStatus('对方没有响应配对请求');
        return;
      }
      const code = window.prompt(`请输入 ${device.name || device.ip} 上显示的 4 位配对码`);
      if (!code) return;
      const result = await pairDevice(device, code.trim());
      if (!result?.token) {
        setStatus('配对码不正确或已过期');
        return;
      }
      await setToken(device.ip, result.token);
      setStatus('配对成功');
      await renderDevices();
    };

    const delBtn = document.createElement('button');
    delBtn.className = 'del';
    delBtn.textContent = '删除';
    delBtn.onclick = async () => {
      await saveDevices(devices.filter((d) => d.ip !== device.ip));
      await renderDevices();
    };

    row.appendChild(label);
    row.appendChild(pushBtn);
    row.appendChild(pairBtn);
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
