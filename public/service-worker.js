self.addEventListener("push", async (event) => {
  let data = {};
  try { data = event.data ? event.data.json() : {}; } catch (e) {}

  const title = data.title || "Homework Planner";
  const options = {
    body: data.body || "",
    icon: "/icon.png",
    badge: "/icon.png",
    data: { path: data.path || "/" }
  };

  event.waitUntil(self.registration.showNotification(title, options));
});

self.addEventListener("notificationclick", function(event) {
  event.notification.close();
  event.waitUntil(
    clients.matchAll({ type: "window" }).then((clientList) => {
      const path = (event.notification.data && event.notification.data.path) || "/";
      for (let client of clientList) {
        if ((new URL(client.url)).pathname === path && "focus" in client) {
          return client.focus();
        }
      }
      if (clients.openWindow) return clients.openWindow(path);
    })
  );
});
