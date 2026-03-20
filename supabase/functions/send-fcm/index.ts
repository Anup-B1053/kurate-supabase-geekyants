import "@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "@supabase/supabase-js";
import { GoogleAuth } from "google-auth-library";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const GOOGLE_CREDENTIALS_JSON = Deno.env.get("GOOGLE_APPLICATION_CREDENTIALS_JSON")!;

const EVENT_TYPE_TITLES: Record<string, string> = {
  like: "New Like",
  must_read: "Must Read",
  comment: "New Comment",
  new_post: "New Post",
  streak_reminder: "Streak Reminder",
  weekly_digest: "Weekly Digest",
};

async function getFcmAccessToken(): Promise<string> {
  const credentials = JSON.parse(GOOGLE_CREDENTIALS_JSON);
  const auth = new GoogleAuth({
    credentials,
    scopes: ["https://www.googleapis.com/auth/firebase.messaging"],
  });
  const client = await auth.getClient();
  const tokenResponse = await client.getAccessToken();
  return tokenResponse.token!;
}

async function sendFcmMessage(
  fcmToken: string,
  title: string,
  body: string,
  data: Record<string, string>,
  projectId: string,
  accessToken: string,
): Promise<{ success: boolean; stale: boolean }> {
  const url = `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`;

  const response = await fetch(url, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${accessToken}`,
    },
    body: JSON.stringify({
      message: {
        token: fcmToken,
        notification: { title, body },
        data,
      },
    }),
  });

  if (response.ok) {
    return { success: true, stale: false };
  }

  const err = await response.json();
  const isStale = err?.error?.details?.some(
    (d: { errorCode?: string }) => d.errorCode === "UNREGISTERED",
  ) ?? false;

  return { success: false, stale: isStale };
}

Deno.serve(async (req) => {
  try {
    const { notification_id } = await req.json();
    if (!notification_id) {
      return new Response(JSON.stringify({ error: "missing notification_id" }), {
        status: 400,
        headers: { "Content-Type": "application/json" },
      });
    }

    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

    // Fetch notification
    const { data: notif, error: notifErr } = await supabase
      .from("notifications")
      .select("recipient_id, event_type, message, actor_id, event_id")
      .eq("id", notification_id)
      .single();

    if (notifErr || !notif) {
      return new Response(JSON.stringify({ error: "notification not found" }), {
        status: 404,
        headers: { "Content-Type": "application/json" },
      });
    }

    // Fetch FCM tokens for the recipient
    const { data: devices, error: devicesErr } = await supabase
      .from("user_devices")
      .select("id, fcm_token")
      .eq("user_id", notif.recipient_id)
      .not("fcm_token", "is", null);

    if (devicesErr || !devices || devices.length === 0) {
      return new Response(JSON.stringify({ sent: 0 }), {
        headers: { "Content-Type": "application/json" },
      });
    }

    const credentials = JSON.parse(GOOGLE_CREDENTIALS_JSON);
    const projectId: string = credentials.project_id;
    const accessToken = await getFcmAccessToken();

    const title = EVENT_TYPE_TITLES[notif.event_type] ?? "Notification";
    const body = notif.message ?? "";
    const data: Record<string, string> = {
      notification_id,
      event_type: notif.event_type,
      ...(notif.event_id ? { event_id: notif.event_id } : {}),
    };

    let sent = 0;
    const staleDeviceIds: string[] = [];

    await Promise.all(
      devices.map(async (device: { id: string; fcm_token: string }) => {
        const result = await sendFcmMessage(
          device.fcm_token,
          title,
          body,
          data,
          projectId,
          accessToken,
        );
        if (result.success) {
          sent++;
        } else if (result.stale) {
          staleDeviceIds.push(device.id);
        }
      }),
    );

    // Remove stale tokens
    if (staleDeviceIds.length > 0) {
      await supabase.from("user_devices").delete().in("id", staleDeviceIds);
    }

    return new Response(JSON.stringify({ sent, stale_removed: staleDeviceIds.length }), {
      headers: { "Content-Type": "application/json" },
    });
  } catch (err) {
    console.error("send-fcm error:", err);
    return new Response(JSON.stringify({ error: String(err) }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }
});
