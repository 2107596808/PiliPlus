// 从 B 站页面提取当前视频信息，供扩展弹窗查询
(() => {
  function readPosition() {
    const video = document.querySelector('video');
    if (video && Number.isFinite(video.currentTime)) {
      return Math.floor(video.currentTime);
    }
    return 0;
  }

  function pageTitle() {
    return document.title.replace('_哔哩哔哩_bilibili', '').trim();
  }

  function parseVideoPage() {
    const url = location.href;
    const isPgc = url.includes('/bangumi/play/');
    const state = window.__INITIAL_STATE__ || {};
    const info = {
      type: isPgc ? 'pgc' : 'ugc',
      bvid: null,
      aid: null,
      cid: null,
      epId: null,
      seasonId: null,
      title: '',
      cover: '',
      position: readPosition(),
    };

    if (isPgc) {
      const epInfo = state.epInfo || state.videoInfo?.epInfo || state.initState?.epInfo || {};
      const epMatch = url.match(/\/bangumi\/play\/(?:ep|ss)(\d+)/);
      info.epId = epMatch ? Number(epMatch[1]) : epInfo.ep_id ?? null;
      info.seasonId = epInfo.season_id ?? state.videoInfo?.season_id ?? null;
      info.aid = epInfo.aid ?? null;
      info.cid = epInfo.cid ?? null;
      info.title = epInfo.title ?? state.videoInfo?.title ?? pageTitle();
      info.cover = epInfo.cover ?? state.videoInfo?.pic ?? '';
    } else {
      const videoData = state.videoData || {};
      const bvMatch = url.match(/\/video\/(BV[0-9A-Za-z]+)/);
      info.bvid = bvMatch ? bvMatch[1] : videoData.bvid ?? null;
      info.aid = videoData.aid ?? null;
      const pMatch = url.match(/[?&]p=(\d+)/);
      const pageIndex = pMatch ? Number(pMatch[1]) - 1 : 0;
      info.cid = videoData.pages?.[pageIndex]?.cid ?? videoData.cid ?? null;
      info.title = videoData.title ?? pageTitle();
      info.cover = videoData.pic ?? '';
    }
    return info;
  }

  chrome.runtime.onMessage.addListener((message, _sender, sendResponse) => {
    if (message?.type === 'getVideoInfo') {
      sendResponse(parseVideoPage());
    }
  });
})();
