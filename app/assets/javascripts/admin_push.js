// Web push for the dashboard. Gets this browser's FCM token through Firebase and registers it as a
// device of the signed-in admin (Admin::PushDevicesController); delivery then reuses the Android
// path (Notifier → PushNotificationJob). The service worker shows the notification and opens it.
//
// The permission prompt only ever follows a click on the button: browsers ignore or permanently
// block prompts that arrive on page load. Once granted, every page load re-registers, which keeps
// the token fresh and puts the row back after a logout removed it. It is one upsert per page view.
const FIREBASE = "https://www.gstatic.com/firebasejs/13.4.0";
const button = document.querySelector("[data-push-toggle]");
const supported = button && "serviceWorker" in navigator && "PushManager" in window && "Notification" in window;

if (supported) {
  if (Notification.permission === "granted") {
    register();
  } else if (Notification.permission === "default") {
    button.hidden = false;
    button.addEventListener("click", async () => {
      button.disabled = true;
      if ((await Notification.requestPermission()) === "granted") await register();
      button.hidden = true;
    });
  }
}

/**
 * Exchanges the browser's push subscription for an FCM token and stores it server-side.
 * Failures only log: a dashboard without push still works.
 */
async function register() {
  try {
    const { vapidKey, ...firebaseConfig } = JSON.parse(button.dataset.pushConfig);
    const [{ initializeApp }, { getMessaging, getToken }] = await Promise.all([
      import(`${FIREBASE}/firebase-app.js`),
      import(`${FIREBASE}/firebase-messaging.js`)
    ]);
    const token = await getToken(getMessaging(initializeApp(firebaseConfig)), {
      vapidKey,
      serviceWorkerRegistration: await navigator.serviceWorker.ready
    });
    if (!token) return;

    await fetch(button.dataset.pushUrl, {
      method: "POST",
      credentials: "same-origin",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content
      },
      body: JSON.stringify({ installation_id: installationId(), token })
    });
  } catch (error) {
    console.warn("[push] registration failed", error);
  }
}

/**
 * A stable id for this browser, so a rotated token updates the same device row instead of adding
 * one (the same role installation_id plays for the Android app).
 */
function installationId() {
  let id = localStorage.getItem("pushInstallationId");
  if (!id) {
    id = `web-${crypto.randomUUID()}`;
    localStorage.setItem("pushInstallationId", id);
  }
  return id;
}
