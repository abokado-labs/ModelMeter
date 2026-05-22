(() => {
  const SNAPSHOT_INTERVAL_MS = 15000;
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

  function usedPercent(section) {
    const usedAfter = section.match(/(100|\d{1,2})(?:\.\d+)?\s*%\s*used/i);
    if (usedAfter) return clampPercent(Number(usedAfter[1]));

    const usedBefore = section.match(/used\s*(100|\d{1,2})(?:\.\d+)?\s*%/i);
    if (usedBefore) return clampPercent(Number(usedBefore[1]));

    const anyPercent = section.match(/(100|\d{1,2})(?:\.\d+)?\s*%/i);
    if (anyPercent) return clampPercent(Number(anyPercent[1]));

    return null;
  }

  function clampPercent(value) {
    if (!Number.isFinite(value)) return null;
    return Math.max(0, Math.min(100, value));
  }

  function resetDetail(section) {
    const match = section.match(/Resets\s+(.*?)(?=\s+(?:(?:100|\d{1,2})(?:\.\d+)?\s*%\s*used|Used|Available|Current usage|Weekly limit|Get\s+\d+x|Upgrade)|$)/i);
    if (!match) return null;
    const value = normalize(match[1]).replace(/\s+(?:100|\d{1,2})(?:\.\d+)?\s*%\s*$/i, "");
    return value ? `Resets ${value}` : null;
  }

  function parseUsagePage() {
    const text = normalize(document.body ? document.body.innerText : "");
    if (!/Usage limits/i.test(text) || !/Current usage/i.test(text) || !/Weekly limit/i.test(text)) {
      return null;
    }

    const currentSection = sectionBetween(text, "Current usage", ["Weekly limit", "Get 20x", "Upgrade"]);
    const weeklySection = sectionBetween(text, "Weekly limit", ["Get 20x", "Upgrade"]);
    const currentUsed = usedPercent(currentSection);
    const weeklyUsed = usedPercent(weeklySection);
    const items = [];

    if (currentUsed !== null) {
      items.push({
        id: "current-usage",
        title: "Current",
        usedPercent: currentUsed,
        detail: resetDetail(currentSection)
      });
    }
    if (weeklyUsed !== null) {
      items.push({
        id: "weekly-limit",
        title: "Weekly",
        usedPercent: weeklyUsed,
        detail: resetDetail(weeklySection)
      });
    }

    if (!items.length) return null;
    return {
      url: location.href,
      title: document.title,
      items,
      visibleTextPreview: text.slice(0, 500)
    };
  }

  function sendSnapshot() {
    const snapshot = parseUsagePage();
    if (!snapshot) return;
    const runtime = globalThis.browser?.runtime || globalThis.chrome?.runtime;
    if (!runtime?.sendMessage) return;
    try {
      runtime.sendMessage({ type: "geminiUsageSnapshot", snapshot });
    } catch (error) {
      console.warn("ModelMeter/Gemini content snapshot send failed", error);
    }
  }

  const observer = new MutationObserver(() => sendSnapshot());
  observer.observe(document.documentElement, { childList: true, subtree: true, characterData: true });
  window.addEventListener("load", sendSnapshot, { once: false });
  document.addEventListener("visibilitychange", sendSnapshot);
  setInterval(sendSnapshot, SNAPSHOT_INTERVAL_MS);
  setTimeout(sendSnapshot, 500);
  setTimeout(sendSnapshot, 2000);
  setTimeout(sendSnapshot, 5000);
})();
