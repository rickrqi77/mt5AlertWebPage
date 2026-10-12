/**
 * GOLD ALERT - Mobile web client
 * Token is entered once per device and remembered; new devices must enter it first.
 */

(function () {
  "use strict";

  const MAX_ALERTS = 15;
  const TOKEN_KEY = "gold_alert_api_token";
  const TOKEN_COOKIE_MAX_AGE = 60 * 60 * 24 * 365 * 10;

  /** @type {Array<{id?: number|null, price: string, enabled: boolean, triggered: boolean}>} */
  let localAlerts = [];
  let toastTimer = null;
  let stepHydrated = false;
  let capturedStep = null;
  let alertsPaused = false;
  let alertsDirty = false;
  let warmupPromise = null;
  let dataReady = false;
  let spotPrice = null;
  let usageTimer = null;

  const $ = (id) => document.getElementById(id);

  // -------------------------------------------------------------------------
  // Auth
  // -------------------------------------------------------------------------

  function cookieFlags() {
    var flags = "; Path=/; SameSite=Lax; Max-Age=" + TOKEN_COOKIE_MAX_AGE;
    if (location.protocol === "https:") flags += "; Secure";
    return flags;
  }

  function readCookie(name) {
    var parts = ("; " + document.cookie).split("; " + name + "=");
    if (parts.length < 2) return "";
    return decodeURIComponent(parts.pop().split(";").shift() || "");
  }

  function writeCookie(name, value) {
    document.cookie = name + "=" + encodeURIComponent(value) + cookieFlags();
  }

  function deleteCookie(name) {
    document.cookie = name + "=; Path=/; SameSite=Lax; Max-Age=0";
  }

  function persistKey(key, value) {
    if (!value) return;
    try {
      localStorage.setItem(key, value);
    } catch {
      /* Safari private mode may block localStorage */
    }
    writeCookie(key, value);
  }

  function persistToken(token) {
    persistKey(TOKEN_KEY, token);
  }

  function readStored(key) {
    var value = "";
    try {
      value = localStorage.getItem(key) || "";
    } catch {
      value = "";
    }
    if (!value) {
      try {
        value = sessionStorage.getItem(key) || "";
      } catch {
        value = "";
      }
    }
    if (!value) value = readCookie(key);
    if (value) persistKey(key, value);
    return value;
  }

  function getToken() {
    return readStored(TOKEN_KEY);
  }

  function setToken(token) {
    persistToken(token);
    try {
      sessionStorage.removeItem(TOKEN_KEY);
    } catch {
      /* ignore */
    }
  }

  function clearStored(key) {
    try {
      localStorage.removeItem(key);
    } catch {
      /* ignore */
    }
    try {
      sessionStorage.removeItem(key);
    } catch {
      /* ignore */
    }
    deleteCookie(key);
  }

  function clearToken() {
    clearStored(TOKEN_KEY);
  }

  function hideAuthError() {
    var errEl = $("auth-error");
    errEl.classList.add("hidden");
    errEl.textContent = "";
  }

  function showAuthError(msg) {
    var errEl = $("auth-error");
    errEl.textContent = msg;
    errEl.classList.remove("hidden");
  }

  function showTokenAuth() {
    $("auth-screen").classList.remove("hidden");
    $("app-screen").classList.add("hidden");
    $("auth-hint").textContent = "新设备输入一次 Token，本机以后不用再输入";
    hideAuthError();
  }

  function showAuth() {
    showTokenAuth();
  }

  function showApp() {
    $("auth-screen").classList.add("hidden");
    $("app-screen").classList.remove("hidden");
  }

  function enterApp() {
    showApp();
    startWarmupAndPoll();
  }

  async function unlock() {
    const token = ($("token-input").value || "").trim();
    hideAuthError();

    if (!token) {
      showAuthError("请输入 API Token");
      return;
    }

    setToken(token);
    await warmupData();
    if (!getToken()) {
      showAuthError("Token 无效");
      return;
    }
    showApp();
  }

  // -------------------------------------------------------------------------
  // API
  // -------------------------------------------------------------------------

  async function api(path, options = {}) {
    const token = getToken();
    const headers = Object.assign(
      { "Content-Type": "application/json" },
      options.headers || {},
      { Authorization: "Bearer " + token }
    );

    const res = await fetch(path, Object.assign({}, options, { headers }));
    let data = null;
    try {
      data = await res.json();
    } catch {
      data = null;
    }

    if (res.status === 401) {
      throw new Error("Unauthorized");
    }
    if (!res.ok) {
      const msg = (data && data.error) || "请求失败 (" + res.status + ")";
      const err = new Error(msg);
      err.code = data && data.code;
      err.status = res.status;
      err.data = data;
      throw err;
    }
    return data;
  }

  // -------------------------------------------------------------------------
  // UI helpers
  // -------------------------------------------------------------------------

  function toast(msg, type) {
    const el = $("toast");
    el.textContent = msg;
    el.className = "toast " + (type || "");
    el.classList.remove("hidden");
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => el.classList.add("hidden"), 2800);
  }

  function formatPrice(n) {
    if (n == null || !Number.isFinite(Number(n))) return "--";
    const v = Number(n);
    // Prefer 2 decimals for gold; keep more if needed
    const s = v.toFixed(Math.abs(v - Math.round(v * 100) / 100) < 1e-9 ? 2 : 3);
    return s;
  }

  function renderPauseButton() {
    const btn = $("btn-pause");
    if (!btn) return;
    if (alertsPaused) {
      btn.textContent = "恢复提醒";
      btn.classList.add("resume");
    } else {
      btn.textContent = "暂停提醒";
      btn.classList.remove("resume");
    }
  }

  async function togglePause() {
    try {
      $("btn-pause").disabled = true;
      const data = await api("/api/pause", {
        method: "POST",
        body: JSON.stringify({ paused: !alertsPaused }),
      });
      alertsPaused = !!data.paused;
      renderPauseButton();
      toast(data.message || (alertsPaused ? "提醒已暂停" : "提醒已恢复"), "success");
    } catch (e) {
      toast(e.message, "error");
    } finally {
      $("btn-pause").disabled = false;
    }
  }

  function armCount() {
    return localAlerts.filter((a) => a.enabled).length;
  }

  function renderAlerts() {
    const list = $("alerts-list");
    $("alerts-count").textContent = "触发 " + armCount() + " / " + localAlerts.length;

    if (localAlerts.length === 0) {
      list.innerHTML = '<li class="empty-hint">暂无提醒，点「设定」生成后选择要触发的价格</li>';
      return;
    }

    list.innerHTML = "";
    localAlerts.forEach((a, idx) => {
      const on = !!a.enabled;
      const used = !on && !!a.triggered;
      const li = document.createElement("li");
      li.className = "alert-item";
      li.innerHTML =
        '<span class="alert-index">' +
        (idx + 1) +
        '.</span>' +
        '<input class="input alert-price-input" type="text" inputmode="decimal" ' +
        'value="' +
        escapeAttr(a.price) +
        '" data-idx="' +
        idx +
        '" />' +
        '<button type="button" class="btn-arm ' +
        (used ? "used" : on ? "on" : "off") +
        '" data-idx="' +
        idx +
        '">' +
        (used ? "已用" : on ? "触发" : "关闭") +
        "</button>" +
        '<button type="button" class="btn-delete" data-idx="' +
        idx +
        '">删除</button>';
      list.appendChild(li);
    });

    list.querySelectorAll(".alert-price-input").forEach((input) => {
      input.addEventListener("change", onPriceEdit);
      input.addEventListener("blur", onPriceEdit);
    });
    list.querySelectorAll(".btn-arm").forEach((btn) => {
      btn.addEventListener("click", onArmClick);
    });
    list.querySelectorAll(".btn-delete").forEach((btn) => {
      btn.addEventListener("click", onDeleteClick);
    });
  }

  function escapeAttr(s) {
    return String(s).replace(/&/g, "&amp;").replace(/"/g, "&quot;").replace(/</g, "&lt;");
  }

  function onPriceEdit(e) {
    const idx = Number(e.target.getAttribute("data-idx"));
    if (!Number.isInteger(idx) || !localAlerts[idx]) return;
    localAlerts[idx].price = e.target.value.trim();
    alertsDirty = true;
  }

  function onArmClick(e) {
    const idx = Number(e.currentTarget.getAttribute("data-idx"));
    if (!Number.isInteger(idx) || !localAlerts[idx]) return;
    localAlerts[idx].enabled = !localAlerts[idx].enabled;
    if (localAlerts[idx].enabled) localAlerts[idx].triggered = false;
    alertsDirty = true;
    renderAlerts();
  }

  function onDeleteClick(e) {
    const idx = Number(e.currentTarget.getAttribute("data-idx"));
    if (!Number.isInteger(idx)) return;
    localAlerts.splice(idx, 1);
    alertsDirty = true;
    renderAlerts();
  }

  function mapAlerts(list) {
    return (list || []).map((a) => ({
      id: a.id,
      price: String(a.price),
      enabled: a.enabled === true || a.enabled === 1,
      triggered: a.triggered === true || a.triggered === 1,
    }));
  }

  function alertsFingerprint(list) {
    return (list || [])
      .map(function (a) {
        return [a.id, a.price, a.enabled ? 1 : 0, a.triggered ? 1 : 0].join(":");
      })
      .join("|");
  }

  // -------------------------------------------------------------------------
  // Data refresh
  // -------------------------------------------------------------------------

  function showQuote(data) {
    $("current-price").textContent = formatPrice(data.price);
    $("bid").textContent = formatPrice(data.bid);
    $("ask").textContent = formatPrice(data.ask);
  }

  async function loadSettings() {
    const data = await api("/api/settings");
    alertsPaused = !!data.paused || data.alerts_enabled === false;
    renderPauseButton();
    if (!stepHydrated && data.step != null) {
      setStepInput(data.step);
      stepHydrated = true;
    }
    return data;
  }

  async function refreshSpot() {
    const btn = $("btn-spot");
    btn.disabled = true;
    try {
      const data = await api("/api/spot");
      spotPrice = Number(data.price);
      showQuote(data);
      $("price-label").textContent = "当前价格";
      $("last-refresh").textContent =
        "刷新 " + new Date().toLocaleTimeString("zh-CN", { hour12: false });
      if (data.usage_request) scheduleUsageOnce(data.usage_request);
      return Number.isFinite(spotPrice) && spotPrice > 0;
    } catch (e) {
      toast(e.message || "现货价格暂时取不到", "error");
      return false;
    } finally {
      btn.disabled = false;
    }
  }

  function scheduleUsageOnce(requestId) {
    if (usageTimer) clearTimeout(usageTimer);
    usageTimer = setTimeout(function () {
      usageTimer = null;
      loadUsageOnce(requestId);
    }, 5000);
  }

  async function loadUsageOnce(requestId) {
    if (!requestId || !canReloadAlertsFromServer()) return;
    try {
      const data = await api("/api/alerts");
      if (Number(data.usage_reported) !== Number(requestId)) return;
      const next = mapAlerts(data.alerts);
      if (alertsFingerprint(next) === alertsFingerprint(localAlerts)) return;
      localAlerts = next;
      alertsDirty = false;
      renderAlerts();
      toast("已更新提醒使用情况", "success");
    } catch (e) {
      if (e.message === "Unauthorized") {
        clearToken();
        showTokenAuth();
      }
    }
  }

  async function loadAlerts(opts) {
    const data = await api("/api/alerts");
    const next = mapAlerts(data.alerts);
    if (opts && opts.skipIfUnchanged && alertsFingerprint(next) === alertsFingerprint(localAlerts)) {
      return;
    }
    localAlerts = next;
    alertsDirty = false;
    renderAlerts();
  }

  function canReloadAlertsFromServer() {
    if (alertsDirty) return false;
    const el = document.activeElement;
    if (el && el.classList && el.classList.contains("alert-price-input")) return false;
    return true;
  }

  async function refreshAll() {
    try {
      await Promise.all([
        loadSettings(),
        canReloadAlertsFromServer()
          ? loadAlerts({ skipIfUnchanged: true })
          : Promise.resolve(),
      ]);
      dataReady = true;
    } catch (e) {
      if (e.message === "Unauthorized") {
        dataReady = false;
        clearToken();
        showTokenAuth();
        return;
      }
      console.warn("refresh failed", e);
    }
  }

  function warmupData() {
    if (!getToken()) return Promise.resolve();
    if (warmupPromise) return warmupPromise;
    warmupPromise = refreshAll().finally(function () {
      warmupPromise = null;
    });
    return warmupPromise;
  }

  function startWarmupAndPoll() {
    if (!getToken()) return;
    warmupData();
  }

  function onPageVisible() {
    if (!getToken()) return;
    if ($("app-screen").classList.contains("hidden")) return;
    alertsDirty = false;
    warmupData();
  }

  // -------------------------------------------------------------------------
  // Actions
  // -------------------------------------------------------------------------

  function collectAlertsFromDom() {
    const inputs = document.querySelectorAll(".alert-price-input");
    if (inputs.length > 0) {
      localAlerts = Array.from(inputs).map((input, i) => ({
        id: localAlerts[i] ? localAlerts[i].id : null,
        price: input.value.trim(),
        enabled: localAlerts[i] ? !!localAlerts[i].enabled : false,
        triggered: localAlerts[i] ? !!localAlerts[i].triggered : false,
      }));
    }
    return localAlerts;
  }

  const STEP_OPTIONS = [1, 2, 3, 4, 5, 10];

  function nearestStep(value) {
    const n = Number(value);
    if (!Number.isFinite(n) || n <= 0) return 5;
    if (STEP_OPTIONS.indexOf(n) >= 0) return n;
    let best = 5;
    let bestDiff = Infinity;
    for (let i = 0; i < STEP_OPTIONS.length; i++) {
      const d = Math.abs(STEP_OPTIONS[i] - n);
      if (d < bestDiff) {
        bestDiff = d;
        best = STEP_OPTIONS[i];
      }
    }
    return best;
  }

  function setStepInput(value) {
    $("step-input").value = String(nearestStep(value));
  }

  function readStep() {
    const raw = capturedStep != null ? capturedStep : Number($("step-input").value);
    capturedStep = null;
    return Number(raw);
  }

  function rememberStep() {
    const n = Number($("step-input").value);
    if (Number.isFinite(n) && n > 0) capturedStep = n;
  }

  async function saveAlerts() {
    collectAlertsFromDom();
    const step = readStep();
    if (!Number.isFinite(step) || step <= 0) {
      toast("间隔必须是大于 0 的数字", "error");
      return;
    }

    const payload = [];
    for (const a of localAlerts) {
      const p = Number(a.price);
      if (!Number.isFinite(p) || p <= 0) {
        toast("存在无效价格：" + a.price, "error");
        return;
      }
      payload.push({
        price: p,
        enabled: !!a.enabled,
        triggered: a.enabled ? 0 : a.triggered ? 1 : 0,
      });
    }

    if (payload.length > MAX_ALERTS) {
      toast("最多 " + MAX_ALERTS + " 个提醒", "error");
      return;
    }

    const armed = payload.filter((a) => a.enabled).length;
    if (payload.length > 0 && armed === 0) {
      if (!confirm("没有点「触发」的价格，EA 不会提醒。仍要保存吗？")) return;
    }

    try {
      $("btn-save").disabled = true;
      const data = await api("/api/alerts", {
        method: "POST",
        body: JSON.stringify({ alerts: payload, step }),
      });
      localAlerts = mapAlerts(data.alerts);
      alertsDirty = false;
      renderAlerts();
      setStepInput(step);
      toast("设置已保存，EA 约 3 秒内取回", "success");
    } catch (e) {
      toast(e.message, "error");
    } finally {
      $("btn-save").disabled = false;
    }
  }

  async function autoGenerate() {
    const step = readStep();
    if (!Number.isFinite(step) || step <= 0) {
      toast("间隔必须是大于 0 的数字", "error");
      return;
    }
    setStepInput(step);

    try {
      $("btn-auto").disabled = true;
      if (!Number.isFinite(spotPrice) || spotPrice <= 0) {
        const ok = await refreshSpot();
        if (!ok) return;
      }

      const data = await api("/api/alerts/auto", {
        method: "POST",
        body: JSON.stringify({ step, price: spotPrice }),
      });
      localAlerts = mapAlerts(data.alerts);
      alertsDirty = false;
      renderAlerts();
      setStepInput(data.step != null ? data.step : step);
      toast(data.message || "已生成，默认全部触发", "success");
    } catch (e) {
      toast(e.message, "error");
    } finally {
      $("btn-auto").disabled = false;
    }
  }

  async function clearAll() {
    if (!confirm("确定清除全部提醒？")) return;
    localAlerts = [];
    renderAlerts();
    try {
      const step = readStep();
      const savedStep = Number.isFinite(step) && step > 0 ? step : 5;
      setStepInput(savedStep);
      await api("/api/alerts", {
        method: "POST",
        body: JSON.stringify({ alerts: [], step: savedStep }),
      });
      toast("已全部清除", "success");
    } catch (e) {
      toast(e.message, "error");
    }
  }

  // -------------------------------------------------------------------------
  // Init
  // -------------------------------------------------------------------------

  function bindEvents() {
    $("btn-unlock").addEventListener("click", unlock);
    $("token-input").addEventListener("keydown", (e) => {
      if (e.key === "Enter") unlock();
    });
    $("btn-logout").addEventListener("click", () => {
      clearToken();
      $("token-input").value = "";
      showTokenAuth();
    });
    $("btn-save").addEventListener("pointerdown", rememberStep);
    $("btn-save").addEventListener("click", saveAlerts);
    $("btn-auto").addEventListener("pointerdown", rememberStep);
    $("btn-auto").addEventListener("click", autoGenerate);
    $("btn-clear").addEventListener("click", clearAll);
    $("step-input").addEventListener("change", rememberStep);
    $("btn-pause").addEventListener("click", togglePause);
    $("btn-spot").addEventListener("click", refreshSpot);
    document.addEventListener("visibilitychange", function () {
      if (document.visibilityState === "visible") onPageVisible();
    });
    window.addEventListener("pageshow", onPageVisible);
  }

  function init() {
    bindEvents();
    if (!getToken()) {
      showTokenAuth();
      return;
    }
    enterApp();
  }

  init();
})();
