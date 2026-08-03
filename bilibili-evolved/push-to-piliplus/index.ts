import { defineComponentMetadata } from '@/components/define'
import { ComponentEntry } from '@/components/types'
import { addControlBarButton } from '@/components/video/video-control-bar'
import { playerAgent } from '@/components/video/player-agent'
import { monkey } from '@/core/ajax'
import { addStyle, removeStyle } from '@/core/style'
import { Toast } from '@/core/toast'
import { playerUrls } from '@/core/utils/urls'
import componentStyle from './style.scss'

const HTTP_PORT = 26982
const APP_ID = 'com.shaoy.piliplus'
const PROTOCOL_VERSION = 1

interface PushOptions {
  deviceIps: string
  subnetPrefix: string
  autoScan: boolean
  senderName: string
}

interface PushedVideoInfo {
  type: 'ugc' | 'pgc'
  bvid: string | null
  aid: number | null
  cid: number | null
  epId: number | null
  seasonId: number | null
  title: string
  cover: string
  positionSec: number
}

interface CastDevice {
  ip: string
  name: string
  receiving: boolean
}

let popup: {
  root: HTMLDivElement
  status: HTMLDivElement
  devices: HTMLUListElement
  videoLine: HTMLDivElement
  scanning: boolean
  found: Map<string, CastDevice>
} | null = null

const getPageState = (): any => {
  const pageWindow = unsafeWindow as Window & { __INITIAL_STATE__?: any }
  return pageWindow.__INITIAL_STATE__ || {}
}

const readVideoInfo = async (): Promise<PushedVideoInfo> => {
  const url = location.href
  const isPgc = url.includes('/bangumi/play/')
  const state = getPageState()
  const titleFallback = document.title.replace('_哔哩哔哩_bilibili', '').trim()
  let positionSec = 0
  try {
    const video = await playerAgent.query.video.element()
    if (video instanceof HTMLVideoElement && Number.isFinite(video.currentTime)) {
      positionSec = Math.floor(video.currentTime)
    }
  } catch {
    // 播放器未就绪时从头开始推
  }
  if (isPgc) {
    const epInfo = state.epInfo || state.videoInfo?.epInfo || state.initState?.epInfo || {}
    const epMatch = url.match(/\/bangumi\/play\/(?:ep|ss)(\d+)/)
    return {
      type: 'pgc',
      bvid: null,
      aid: epInfo.aid ?? null,
      cid: epInfo.cid ?? null,
      epId: epMatch ? Number(epMatch[1]) : epInfo.ep_id ?? null,
      seasonId: epInfo.season_id ?? state.videoInfo?.season_id ?? null,
      title: epInfo.title ?? state.videoInfo?.title ?? titleFallback,
      cover: epInfo.cover ?? state.videoInfo?.pic ?? '',
      positionSec,
    }
  }
  const videoData = state.videoData || {}
  const bvMatch = url.match(/\/video\/(BV[0-9A-Za-z]+)/)
  const pMatch = url.match(/[?&]p=(\d+)/)
  const pageIndex = pMatch ? Number(pMatch[1]) - 1 : 0
  return {
    type: 'ugc',
    bvid: bvMatch ? bvMatch[1] : videoData.bvid ?? null,
    aid: videoData.aid ?? null,
    cid: videoData.pages?.[pageIndex]?.cid ?? videoData.cid ?? null,
    epId: null,
    seasonId: null,
    title: videoData.title ?? titleFallback,
    cover: videoData.pic ?? '',
    positionSec,
  }
}

const pingDevice = async (ip: string): Promise<CastDevice | null> => {
  try {
    const raw = await monkey<string>({
      url: `http://${ip}:${HTTP_PORT}/ping`,
      method: 'GET',
      timeout: 1000,
      responseType: 'text',
    })
    const data = JSON.parse(raw)
    if (data?.app !== APP_ID) {
      return null
    }
    return {
      ip,
      name: data.name || ip,
      receiving: Boolean(data.receiving),
    }
  } catch {
    return null
  }
}

const scanSubnet = async (
  prefix: string,
  onProgress?: (found: CastDevice[]) => void,
): Promise<CastDevice[]> => {
  const found: CastDevice[] = []
  const hosts = Array.from({ length: 254 }, (_, i) => `${prefix}.${i + 1}`)
  for (let i = 0; i < hosts.length; i += 20) {
    const batch = hosts.slice(i, i + 20)
    const devices = await Promise.all(batch.map(ip => pingDevice(ip)))
    for (const device of devices) {
      if (device) {
        found.push(device)
      }
    }
    onProgress?.(found)
  }
  return found
}

const createUuid = () =>
  typeof crypto !== 'undefined' && 'randomUUID' in crypto
    ? crypto.randomUUID()
    : `${Date.now()}-${Math.random().toString(36).slice(2)}`

const pushToDevice = async (
  ip: string,
  info: PushedVideoInfo,
  senderName: string,
): Promise<boolean> => {
  const message = {
    t: 'push',
    id: createUuid(),
    v: PROTOCOL_VERSION,
    app: APP_ID,
    from: senderName,
    payload: {
      type: info.type,
      bvid: info.bvid,
      aid: info.aid,
      cid: info.cid,
      epId: info.epId,
      seasonId: info.seasonId,
      title: info.title,
      cover: info.cover,
      positionSec: info.positionSec,
    },
  }
  try {
    const raw = await monkey<string>({
      url: `http://${ip}:${HTTP_PORT}/push`,
      method: 'POST',
      timeout: 5000,
      responseType: 'text',
      headers: { 'Content-Type': 'application/json' },
      data: JSON.stringify(message),
    })
    return JSON.parse(raw)?.t === 'ack'
  } catch {
    return false
  }
}

const setStatus = (text: string) => {
  if (popup) {
    popup.status.textContent = text
  }
}

const renderDeviceList = (devices: CastDevice[]) => {
  if (!popup) {
    return
  }
  const { devices: list } = popup
  list.textContent = ''
  if (devices.length === 0) {
    const empty = document.createElement('li')
    empty.className = 'be-push-empty'
    empty.textContent = popup.scanning ? '正在扫描设备…' : '没有可用设备，请添加设备 IP 或扫描局域网'
    list.appendChild(empty)
    return
  }
  for (const device of devices) {
    const row = document.createElement('li')
    row.className = 'be-push-device'
    const label = document.createElement('div')
    label.className = 'be-push-device-name'
    const name = document.createElement('div')
    name.className = 'name'
    name.textContent = device.name
    const ip = document.createElement('div')
    ip.className = 'ip'
    ip.textContent = device.ip
    label.appendChild(name)
    label.appendChild(ip)
    const badge = document.createElement('div')
    badge.className = `be-push-badge${device.receiving ? '' : ' off'}`
    badge.textContent = device.receiving ? '接收中' : '未开启接收'
    row.appendChild(label)
    row.appendChild(badge)
    row.addEventListener('click', () => {
      void pushAndClose(device.ip)
    })
    list.appendChild(row)
  }
}

const refreshSavedDevices = async () => {
  if (!popup) {
    return
  }
  const options = popup.options
  const ips = options.deviceIps
    .split(/\r?\n/)
    .map(ip => ip.trim())
    .filter(Boolean)
  const saved = (await Promise.all(ips.map(ip => pingDevice(ip)))).filter(
    (device): device is CastDevice => device !== null,
  )
  if (!popup) {
    return
  }
  for (const device of saved) {
    popup.found.set(device.ip, device)
  }
  renderDeviceList([...popup.found.values()])
}

const startScan = async () => {
  if (!popup || popup.scanning) {
    return
  }
  const prefix = popup.options.subnetPrefix.trim()
  if (!prefix) {
    Toast.info('请先在组件设置中填写局域网网段（如 192.168.1）', '推送到 PiliPlus')
    return
  }
  popup.scanning = true
  setStatus('正在扫描局域网…')
  await scanSubnet(prefix, found => {
    if (!popup) {
      return
    }
    for (const device of found) {
      popup.found.set(device.ip, device)
    }
    renderDeviceList([...popup.found.values()])
  })
  if (popup) {
    popup.scanning = false
    setStatus(`扫描完成，共发现 ${popup.found.size} 台设备`)
  }
}

const pushAndClose = async (ip: string) => {
  if (!popup) {
    return
  }
  const { videoInfo, options } = popup
  setStatus(`正在推送到 ${ip}…`)
  const ok = await pushToDevice(ip, videoInfo, options.senderName)
  if (!popup) {
    return
  }
  if (ok) {
    closePopup()
    Toast.success(`已推送《${videoInfo.title}》，接收端确认后将继续播放`, '推送到 PiliPlus')
  } else {
    setStatus('推送失败，请确认设备在线且已开启「接收设备推送」')
  }
}

const closePopup = () => {
  popup?.root.remove()
  popup = null
}

const showPopup = async (videoInfo: PushedVideoInfo, options: PushOptions) => {
  closePopup()
  const root = document.createElement('div')
  root.className = 'be-push-piliplus-overlay'
  root.innerHTML = `
    <div class="be-push-piliplus-panel">
      <header class="be-push-header">
        <span class="be-push-title">推送到 PiliPlus 设备</span>
        <button class="be-push-close" type="button">×</button>
      </header>
      <div class="be-push-video"></div>
      <div class="be-push-status"></div>
      <ul class="be-push-devices"></ul>
      <footer class="be-push-toolbar">
        <input class="be-push-ip-input" placeholder="输入设备 IP，如 192.168.1.100" />
        <button class="be-push-button be-push-add" type="button">添加</button>
        <button class="be-push-button be-push-scan" type="button">扫描</button>
      </footer>
    </div>
  `
  const status = root.querySelector('.be-push-status') as HTMLDivElement
  const devices = root.querySelector('.be-push-devices') as HTMLUListElement
  const videoLine = root.querySelector('.be-push-video') as HTMLDivElement
  const idText = videoInfo.bvid || (videoInfo.epId ? `ep${videoInfo.epId}` : '')
  videoLine.textContent = `《${videoInfo.title || '未知视频'}》 · ${idText}${
    videoInfo.positionSec > 0 ? ` · 进度 ${videoInfo.positionSec} 秒` : ''
  }`

  popup = {
    root,
    status,
    devices,
    videoLine,
    scanning: false,
    found: new Map<string, CastDevice>(),
    videoInfo,
    options,
  }

  root.querySelector('.be-push-close')?.addEventListener('click', closePopup)
  root.addEventListener('click', event => {
    if (event.target === root) {
      closePopup()
    }
  })
  root.querySelector('.be-push-scan')?.addEventListener('click', () => {
    void startScan()
  })
  const ipInput = root.querySelector('.be-push-ip-input') as HTMLInputElement
  root.querySelector('.be-push-add')?.addEventListener('click', async () => {
    const ip = ipInput.value.trim()
    if (!ip) {
      return
    }
    setStatus(`正在连接 ${ip}…`)
    const device = await pingDevice(ip)
    if (!popup) {
      return
    }
    if (!device) {
      setStatus('无法连接该设备，请确认 IP 正确且设备已安装新版 PiliPlus')
      return
    }
    popup.found.set(ip, device)
    renderDeviceList([...popup.found.values()])
    setStatus(`已添加 ${device.name}（${device.receiving ? '接收中' : '未开启接收'}）`)
    ipInput.value = ''
  })
  document.body.appendChild(root)

  setStatus('正在检测已保存的设备…')
  await refreshSavedDevices()
  if (options.autoScan && options.subnetPrefix.trim()) {
    void startScan()
  }
}

const entry: ComponentEntry<PushOptions> = async ({ settings }) => {
  addStyle(componentStyle, 'pushToPiliPlus')
  addControlBarButton({
    name: 'pushToPiliPlus',
    displayName: '推送到 PiliPlus',
    icon: 'mdi-send',
    order: 100,
    action: async () => {
      const info = await readVideoInfo()
      if (!info.cid || (!info.bvid && !info.epId)) {
        Toast.error('未识别到可推送的视频，请在视频播放页使用', '推送到 PiliPlus')
        return
      }
      void showPopup(info, settings.options)
    },
  })
}

export const component = defineComponentMetadata<PushOptions>({
  name: 'pushToPiliPlus',
  displayName: '推送到 PiliPlus 设备',
  author: {
    name: '2107596808',
    link: 'https://github.com/2107596808',
  },
  tags: [componentsTags.video],
  urlInclude: playerUrls,
  entry,
  options: {
    deviceIps: {
      displayName: '设备 IP（每行一个）',
      defaultValue: '',
      multiline: true,
    },
    subnetPrefix: {
      displayName: '局域网网段（如 192.168.1，用于扫描）',
      defaultValue: '',
    },
    autoScan: {
      displayName: '打开面板时自动扫描网段',
      defaultValue: true,
    },
    senderName: {
      displayName: '发送端名称',
      defaultValue: '电脑浏览器',
    },
  },
  reload: () => {
    addStyle(componentStyle, 'pushToPiliPlus')
    closePopup()
  },
  unload: () => {
    removeStyle('pushToPiliPlus')
    closePopup()
  },
})
