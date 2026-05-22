const NATIVE_APP_ID = "com.bobkitchen.ModelMeter";
const GEMINI_USAGE_URL = "https://gemini.google.com/usage";
const REFRESH_ALARM_NAME = "gemini-usage-refresh";
const REFRESH_MINUTES = 5;


let nativePort = null;

function connectNativePort() {
  try {
    nativePort = browser.runtime.connectNative(NATIVE_APP_ID);
    console.log("ModelMeter/Gemini native port connected");
    postNativeDiagnostic("native-port-connected");
    nativePort.onMessage.addListener((message) => {
      console.log("ModelMeter/Gemini native port message", message);
      postNativeDiagnostic("native-port-message", { message });
      refreshFromBackgroundFetch();
    });
    nativePort.onDisconnect.addListener(() => {
      console.warn("ModelMeter/Gemini native port disconnected", browser.runtime.lastError);
      postNativeDiagnostic("native-port-disconnected", { error: String(browser.runtime.lastError || "unknown") });
      nativePort = null;
    });
  } catch (error) {
    console.warn("ModelMeter/Gemini native port connection failed", error);
    postNativeDiagnostic("native-port-connect-failed", { error: String(error) });
  }
}


async function postNativeDiagnostic(event, details = {}) {
  try {
    const response = await browser.runtime.sendNativeMessage(NATIVE_APP_ID, {
      type: "diagnostic",
      event,
      source: "safari-background-script",
      details,
      timestamp: new Date().toISOString()
    });
    console.log("ModelMeter/Gemini diagnostic response", event, response);
  } catch (error) {
    console.warn("ModelMeter/Gemini diagnostic native message failed", event, error);
  }
}

function normalize(text) {
  return String(text || "").replace(/\s+/g, " ").trim();
}

function sectionBetween(text, startLabel, endLabels) {
  const lower = text.toLowerCase();
  const start = lower.indexOf(startLabel.toLowerCase());
  if (start < 0) return "";
  const afterStartIndex = start + startLabel.length;
  const after = text.slice(afterStartIndex);
  const lowerAfter = after.toLowerCase();
  let end = after.length;
  for (const label of endLabels) {
    const idx = lowerAfter.indexOf(label.toLowerCase());
    if (idx >= 0 && idx < end) end = idx;
  }
  return normalize(after.slice(0, end));
}

function clampPercent(value) {
  if (!Number.isFinite(value)) return null;
  return Math.max(0, Math.min(100, value));
}

function usedPercent(section) {
  const usedAfter = section.match(/(100|\d{1,2})(?:\.\d+)?\s*%\s*used/i);
  if (usedAfter) return clampPercent(Number(usedAfter[1]));

  const usedBefore = section.match(/used\s*(100|\d{1,2})(?:\.\d+)?\s*%/i);
  if (usedBefore) return clampPercent(Number(usedBefore[1]));

  const anyPercent = section.match(/(100|\d{1,2})(?:\.\d+)?\s*%/i);
  if (anyPercent) return clampPercent(Number(anyPercent[1]));

  return null;
}

function resetDetail(section) {
  const match = section.match(/Resets\s+(.*?)(?=\s+(?:(?:100|\d{1,2})(?:\.\d+)?\s*%\s*used|Used|Available|Current usage|Weekly limit|Get\s+\d+x|Upgrade)|$)/i);
  if (!match) return null;
  const value = normalize(match[1]).replace(/\s+(?:100|\d{1,2})(?:\.\d+)?\s*%\s*$/i, "");
  return value ? `Resets ${value}` : null;
}

function htmlToText(html) {
  try {
    return normalize(new DOMParser().parseFromString(html, "text/html").body?.innerText || "");
  } catch (_) {
    return normalize(html.replace(/<script[\s\S]*?<\/script>/gi, " ").replace(/<style[\s\S]*?<\/style>/gi, " ").replace(/<[^>]+>/g, " "));
  }
}

function parseUsageText(text, source, url = GEMINI_USAGE_URL, title = "Gemini Usage") {
  text = normalize(text);
  if (!/Usage limits/i.test(text) || !/Current usage/i.test(text) || !/Weekly limit/i.test(text)) {
    return null;
  }

  const currentSection = sectionBetween(text, "Current usage", ["Weekly limit", "Get 20x", "Upgrade"]);
  const weeklySection = sectionBetween(text, "Weekly limit", ["Get 20x", "Upgrade"]);
  const currentUsed = usedPercent(currentSection);
  const weeklyUsed = usedPercent(weeklySection);
  const items = [];

  if (currentUsed !== null) {
    items.push({ id: "current-usage", title: "Current", usedPercent: currentUsed, detail: resetDetail(currentSection) });
  }
  if (weeklyUsed !== null) {
    items.push({ id: "weekly-limit", title: "Weekly", usedPercent: weeklyUsed, detail: resetDetail(weeklySection) });
  }

  if (!items.length) return null;
  return { url, title, items, source, visibleTextPreview: text.slice(0, 500) };
}

async function postNative(snapshot) {
  if (!snapshot?.items?.length) return false;
  try {
    const response = await browser.runtime.sendNativeMessage(NATIVE_APP_ID, snapshot);
    console.log("ModelMeter/Gemini native response", response);
    return !!response?.ok;
  } catch (error) {
    console.warn("ModelMeter/Gemini native message failed", error);
    return false;
  }
}

async function refreshFromBackgroundFetch() {
  postNativeDiagnostic("background-fetch-started", { url: GEMINI_USAGE_URL });
  try {
    const response = await fetch(GEMINI_USAGE_URL, {
      credentials: "include",
      cache: "no-store",
      headers: { "Accept": "text/html,application/xhtml+xml" }
    });
    const html = await response.text();
    const snapshot = parseUsageText(htmlToText(html), "safari-background-fetch", response.url || GEMINI_USAGE_URL, "Gemini Usage");
    if (snapshot) {
      postNativeDiagnostic("background-fetch-found-usage", { status: response.status, url: response.url, items: snapshot.items.length });
      await postNative(snapshot);
    } else {
      const detail = {
        status: response.status,
        url: response.url,
        preview: normalize(htmlToText(html)).slice(0, 240)
      };
      console.log("ModelMeter/Gemini background fetch did not find usage data", detail);
      postNativeDiagnostic("background-fetch-no-usage", detail);
    }
  } catch (error) {
    console.warn("ModelMeter/Gemini background fetch failed", error);
    postNativeDiagnostic("background-fetch-failed", { error: String(error) });
  }
}

browser.runtime.onMessage.addListener((message) => {
  if (message?.type === "geminiUsageSnapshot") {
    return postNative({ ...message.snapshot, source: "safari-content-script" }).then((ok) => ({ ok }));
  }
  if (message?.type === "refreshGeminiUsage") {
    return refreshFromBackgroundFetch().then(() => ({ ok: true }));
  }
  return false;
});

browser.runtime.onMessageExternal?.addListener((message, sender) => {
  console.log("ModelMeter/Gemini external message", message, sender);
  postNativeDiagnostic("external-message", {
    message,
    senderId: sender?.id || null,
    senderUrl: sender?.url || null
  });

  return refreshFromBackgroundFetch().then(() => ({ ok: true }));
});

browser.runtime.onInstalled?.addListener(() => {
  browser.alarms.create(REFRESH_ALARM_NAME, { periodInMinutes: REFRESH_MINUTES });
  refreshFromBackgroundFetch();
});

browser.runtime.onStartup?.addListener(() => {
  browser.alarms.create(REFRESH_ALARM_NAME, { periodInMinutes: REFRESH_MINUTES });
  refreshFromBackgroundFetch();
});

browser.alarms?.onAlarm.addListener((alarm) => {
  if (alarm.name === REFRESH_ALARM_NAME) refreshFromBackgroundFetch();
});

browser.alarms?.create(REFRESH_ALARM_NAME, { periodInMinutes: REFRESH_MINUTES });
refreshFromBackgroundFetch();

connectNativePort();

postNativeDiagnostic("background-script-loaded");
