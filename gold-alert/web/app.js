/**
 * GOLD ALERT - OneDrive file sync. No Cloudflare polling.
 * Price is read only when the user taps 设定.
 */

(function () {
  "use strict";

  const MAX_ALERTS = 15;
  const AUTO_GRID_SIDE = 7;
  const CLIENT_ID_KEY = "gold_alert_azure_client_id";
  const GRAPH_SCOPES = ["User.Read", "Files.ReadWrite"];
  const OD_FOLDER = "gold-alert";
  const EA_ONLINE_SECONDS = 45;

  /** @type {Array<{id?: number|null, price: string, enabled: boolean, triggered: boolean}>} */
  let localAlerts = [];
  let toastTimer = null;
  let capturedStep = null;
  let alertsPaused = false;
  let alertsDirty = false;
  let pca = null;
  let graphToken = "";

  const $ = (id) => document.getElementById(id);

  function persist(key, value) {
    try {
      if (value) localStorage.setItem(key, value);
      else localStorage.removeItem(key);
    } catch {
      /* ignore */
    }
  }

  function readStored(key) {
    try {
      return localStorage.getItem(key) || "";
    } catch {
      return "";
    }
  }

  function getClientId() {
    return ($("azure-client-id") && $("azure-client-id").value.trim()) || readStored(CLIENT_ID_KEY);
  }

  function hideAuthError() {
    $("auth-error").classList.add("hidden");
    $("auth-error").textContent = "";
  }

  function showAuthError(msg) {
    $("auth-error").textContent = msg;
    $("auth-error").classList.remove("hidden");
  }

  function showAuth() {
    $("auth-screen").classList.remove("hidden");
    $("app-screen").classList.add("hidden");
    var saved = readStored(CLIENT_ID_KEY);
    if (saved && $("azure-client-id")) $("azure-client-id").value = saved;
    hideAuthError();
  }

  function showApp() {
    $("auth-screen").classList.add("hidden");
    $("app-screen").classList.remove("hidden");
  }

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

  function renderEaStatus(online) {
    const el = $("ea-status");
    const text = $("ea-status-text");
    if (online) {
      el.classList.add("online");
      el.classList.remove("offline");
      text.textContent = "🟢 EA 在线";
    } else {
      el.classList.add("offline");
      el.classList.remove("online");
      text.textContent = "🔴 EA 离线";
    }
  }

  function applyStatus(data) {
    if (!data) return;
    $("symbol").textContent = data.symbol || "XAUUSD";
    $("current-price").textContent = formatPrice(data.price);
    $("bid").textContent = formatPrice(data.bid);
    $("ask").textContent = formatPrice(data.ask);
    var ts = Number(data.ts);
    var online = Number.isFinite(ts) && Math.abs(Date.now() / 1000 - ts) <= EA_ONLINE_SECONDS;
    renderEaStatus(online);
    $("last-refresh").textContent =
      "取价 " + new Date().toLocaleTimeString("zh-CN", { hour12: false });
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
        (on ? "on" : "off") +
        '" data-idx="' +
        idx +
        '">' +
        (on ? "触发" : "关闭") +
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

  function roundPrice(p) {
    return Math.round(p * 100000) / 100000;
  }

  function autoGenerateLocal(currentPrice, step) {
    const base = Math.trunc(currentPrice);
    const prices = [];
    for (let i = AUTO_GRID_SIDE; i >= 1; i--) {
      prices.push({ price: String(roundPrice(base - step * i)), enabled: true, triggered: false });
    }
    prices.push({ price: String(roundPrice(base)), enabled: false, triggered: false });
    for (let i = 1; i <= AUTO_GRID_SIDE; i++) {
      prices.push({ price: String(roundPrice(base + step * i)), enabled: true, triggered: false });
    }
    return prices;
  }

  function alertsToFile(list, step) {
    var lines = ["# gold-alert", "# step=" + step];
    (list || []).forEach(function (a) {
      var p = String(a.price).trim();
      if (!p) return;
      lines.push(a.enabled ? p : "!" + p);
    });
    return lines.join("\n") + "\n";
  }

  function fileToAlerts(text) {
    var list = [];
    String(text || "")
      .split(/\r?\n/)
      .forEach(function (line) {
        line = line.trim();
        if (!line || line.charAt(0) === "#") return;
        var enabled = true;
        if (line.charAt(0) === "!") {
          enabled = false;
          line = line.slice(1).trim();
        }
        var p = Number(line.split(",")[0]);
        if (!Number.isFinite(p) || p <= 0) return;
        list.push({ price: String(p), enabled: enabled, triggered: false });
      });
    return list;
  }

  function redirectUri() {
    return location.origin + "/";
  }

  function ensureMsal() {
    if (typeof msal === "undefined") throw new Error("登录组件未加载，请刷新页面");
    var clientId = getClientId();
    if (!clientId) throw new Error("请先填写 Azure 应用 ID");
    persist(CLIENT_ID_KEY, clientId);
    if (pca) return pca;
    pca = new msal.PublicClientApplication({
      auth: {
        clientId: clientId,
        authority: "https://login.microsoftonline.com/common",
        redirectUri: redirectUri(),
      },
      cache: { cacheLocation: "localStorage" },
    });
    return pca;
  }

  async function getGraphToken() {
    var app = ensureMsal();
    await app.initialize();
    var account = app.getAllAccounts()[0];
    if (!account) throw new Error("请先登录 Microsoft");
    try {
      var silent = await app.acquireTokenSilent({ scopes: GRAPH_SCOPES, account: account });
      graphToken = silent.accessToken;
      return graphToken;
    } catch (e) {
      var pop = await app.acquireTokenPopup({ scopes: GRAPH_SCOPES, account: account });
      graphToken = pop.accessToken;
      return graphToken;
    }
  }

  function graphHeaders(extra) {
    return Object.assign({ Authorization: "Bearer " + graphToken }, extra || {});
  }

  function drivePath(name) {
    return (
      "https://graph.microsoft.com/v1.0/me/drive/root:/" +
      OD_FOLDER +
      "/" +
      name +
      ":/content"
    );
  }

  async function ensureFolder() {
    var res = await fetch("https://graph.microsoft.com/v1.0/me/drive/root:/" + OD_FOLDER, {
      headers: graphHeaders(),
    });
    if (res.ok) return;
    if (res.status !== 404) {
      throw new Error("无法访问 OneDrive 文件夹 (" + res.status + ")");
    }
    var created = await fetch("https://graph.microsoft.com/v1.0/me/drive/root/children", {
      method: "POST",
      headers: graphHeaders({ "Content-Type": "application/json" }),
      body: JSON.stringify({
        name: OD_FOLDER,
        folder: {},
        "@microsoft.graph.conflictBehavior": "fail",
      }),
    });
    if (!created.ok && created.status !== 409) {
      throw new Error("无法创建 gold-alert 文件夹");
    }
  }

  async function graphGetText(name) {
    await getGraphToken();
    var res = await fetch(drivePath(name), { headers: graphHeaders() });
    if (res.status === 404) return "";
    if (!res.ok) throw new Error("读取 " + name + " 失败 (" + res.status + ")");
    return await res.text();
  }

  async function graphPutText(name, text) {
    await getGraphToken();
    await ensureFolder();
    var res = await fetch(drivePath(name), {
      method: "PUT",
      headers: graphHeaders({ "Content-Type": "text/plain; charset=utf-8" }),
      body: text,
    });
    if (!res.ok) throw new Error("写入 OneDrive 失败 (" + res.status + ")");
  }

  async function loadAlertsFromDrive() {
    var text = await graphGetText("alerts.txt");
    localAlerts = fileToAlerts(text);
    alertsDirty = false;
    renderAlerts();
    var paused = (await graphGetText("paused.txt")).trim();
    alertsPaused = paused === "1" || paused.toLowerCase() === "true";
    renderPauseButton();
  }

  async function saveAlertsToDrive() {
    collectAlertsFromDom();
    const step = readStep();
    if (!Number.isFinite(step) || step <= 0) {
      toast("间隔必须是大于 0 的数字", "error");
      return;
    }
    if (localAlerts.length > MAX_ALERTS) {
      toast("最多 " + MAX_ALERTS + " 个提醒", "error");
      return;
    }
    for (const a of localAlerts) {
      const p = Number(a.price);
      if (!Number.isFinite(p) || p <= 0) {
        toast("存在无效价格：" + a.price, "error");
        return;
      }
    }
    const armed = localAlerts.filter((a) => a.enabled).length;
    if (localAlerts.length > 0 && armed === 0) {
      if (!confirm("没有点「触发」的价格，EA 不会提醒。仍要保存吗？")) return;
    }
    $("btn-save").disabled = true;
    try {
      await graphPutText("alerts.txt", alertsToFile(localAlerts, step));
      alertsDirty = false;
      toast("已写入 OneDrive，电脑 EA 稍后会同步", "success");
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
    $("btn-auto").disabled = true;
    try {
      var raw = await graphGetText("status.json");
      if (!raw) throw new Error("还没有现价。请先让电脑 EA 运行并同步 OneDrive");
      var status = JSON.parse(raw);
      var price = Number(status.price);
      if (!Number.isFinite(price) || price <= 0) throw new Error("现价无效");
      applyStatus(status);
      if (
        status.ts &&
        Math.abs(Date.now() / 1000 - Number(status.ts)) > EA_ONLINE_SECONDS
      ) {
        toast("EA 现价较旧，请确认电脑在线后再设定", "error");
        return;
      }
      localAlerts = autoGenerateLocal(price, step);
      alertsDirty = false;
      renderAlerts();
      await graphPutText("alerts.txt", alertsToFile(localAlerts, step));
      toast("已按现价设定并写入 OneDrive", "success");
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
      await graphPutText("alerts.txt", "# gold-alert\n");
      toast("已全部清除", "success");
    } catch (e) {
      toast(e.message, "error");
    }
  }

  async function togglePause() {
    try {
      $("btn-pause").disabled = true;
      alertsPaused = !alertsPaused;
      await graphPutText("paused.txt", alertsPaused ? "1\n" : "0\n");
      renderPauseButton();
      toast(alertsPaused ? "提醒已暂停" : "提醒已恢复", "success");
    } catch (e) {
      alertsPaused = !alertsPaused;
      toast(e.message, "error");
    } finally {
      $("btn-pause").disabled = false;
    }
  }

  async function loginMicrosoft() {
    hideAuthError();
    try {
      var app = ensureMsal();
      await app.initialize();
      persist(CLIENT_ID_KEY, getClientId());
      var result = await app.handleRedirectPromise();
      if (result && result.account) {
        await enterApp();
        return;
      }
      if (app.getAllAccounts().length > 0) {
        await enterApp();
        return;
      }
      await app.loginRedirect({ scopes: GRAPH_SCOPES });
    } catch (e) {
      showAuthError(e.message || String(e));
    }
  }

  async function enterApp() {
    showApp();
    try {
      await loadAlertsFromDrive();
    } catch (e) {
      toast("已登录。点「设定」会取现价并写入 OneDrive", "success");
    }
  }

  async function logout() {
    try {
      var app = ensureMsal();
      await app.initialize();
      var account = app.getAllAccounts()[0];
      if (account) {
        await app.logoutRedirect({ account: account });
        return;
      }
    } catch {
      /* ignore */
    }
    graphToken = "";
    showAuth();
  }

  function bindEvents() {
    $("btn-unlock").addEventListener("click", loginMicrosoft);
    $("btn-logout").addEventListener("click", logout);
    $("btn-save").addEventListener("pointerdown", rememberStep);
    $("btn-save").addEventListener("click", saveAlertsToDrive);
    $("btn-auto").addEventListener("pointerdown", rememberStep);
    $("btn-auto").addEventListener("click", autoGenerate);
    $("btn-clear").addEventListener("click", clearAll);
    $("step-input").addEventListener("change", rememberStep);
    $("btn-pause").addEventListener("click", togglePause);
    $("azure-client-id").addEventListener("change", function () {
      persist(CLIENT_ID_KEY, getClientId());
    });
  }

  async function init() {
    bindEvents();
    var saved = readStored(CLIENT_ID_KEY);
    if (saved) $("azure-client-id").value = saved;
    showAuth();
    if (!saved || typeof msal === "undefined") return;
    try {
      var app = ensureMsal();
      await app.initialize();
      var result = await app.handleRedirectPromise();
      if (result || app.getAllAccounts().length > 0) await enterApp();
    } catch (e) {
      showAuthError(e.message || String(e));
    }
  }

  init();
})();
