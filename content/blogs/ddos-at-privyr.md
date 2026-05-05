---
title: "Under Fire: What a Real DDoS Attack Looks Like and How We Fought Back"
date: 2025-09-12T10:00:00+08:00
draft: false
description: "What a real DDoS attack looks like up close, how we responded in real time at Privyr, the tools that helped us survive 30 hours of it, and the product change we shipped right after."
tags: [ddos, security, cloudflare, aws, incident-response, devops]
---

It was a Tuesday afternoon, around 3pm. We were deep into sprint planning when the Slack messages started coming in.

"I can't log in."
"The app is really slow."
"Is something wrong with Privyr?"

The first instinct was to look for a simpler explanation. Maybe a flaky deploy. Maybe a user on a slow connection. Then more messages. Then a lot more.

I tried to SSH into the box. It would not connect. CPU was pegged. I pulled up the metrics dashboards and stared at the graphs for a few seconds. Request counts were off the charts. Response times had collapsed. This was not a bug.

We were under a DDoS attack.

{{< figure src="/img/for_blogs/ddos_war_room.png" title="Two engineers watching spiking ALB dashboards during the incident" >}}

## What a war of attrition looks like

DDoS attacks are not always about knocking you offline in one dramatic hit. This one was a war of attrition. Thousands of requests hammering our login and signup endpoints with random data, from a distributed set of IPs, sustained over hours. The goal is simple: exhaust your resources until real users cannot get through.

At the time, we had no CAPTCHA on the login flow. That made us an easy target. No friction for bots, nothing to slow them down.

Two of us set up a war room. One person watched ALB metrics. The other dug through access logs. We took turns trying different mitigations, watching the graphs, adjusting. This went on through the evening, through the night, and into the next morning.

The attack lasted roughly 30 to 35 hours total.

## What we actually did

Here is the playbook we ran, roughly in order. If you are reading this during an incident, skip to the action and come back for the explanation later.

### 1. Cloudflare: Under Attack Mode

The first thing we did was go to the Cloudflare dashboard and enable **Under Attack Mode** under Quick Actions. This makes Cloudflare show every visitor a JavaScript challenge before passing traffic through to your origin. Bots generally cannot pass this challenge.

It buys you time. It is not a permanent fix, but it is the fastest lever you have.

### 2. Check DNS is proxied through Cloudflare

If your DNS records are set to DNS only (the grey cloud in Cloudflare), traffic bypasses Cloudflare entirely and hits your origin directly. Make sure the record for your domain is set to **Proxied** (the orange cloud). If it is not, Cloudflare cannot protect you.

This seems obvious but it is easy to miss under pressure.

### 3. Rate limiting on the abused endpoints

In our case the attack was concentrated on the login and signup APIs. Cloudflare lets you set rate limit rules per URL pattern. For example, block any IP that makes more than N requests to `/login` within a 60 second window.

Go to **Security Rules** in Cloudflare and set up rate limit rules targeting the endpoints getting hammered. Be conservative at first, then tighten them as you understand the pattern.

### 4. Dig into the access logs with Athena

While Cloudflare does the heavy lifting at the edge, you also want to understand what is happening at the origin level. We used **AWS Athena** to query our ALB access logs directly.

The query we ran grouped requests by client IP and URL, sorted by request count:

```sql
SELECT
    client_ip,
    request_url,
    COUNT(*) AS request_count,
    AVG(target_processing_time) AS avg_latency_seconds
FROM
    <your_alb_logs_table>
WHERE
    day = '<target_date>'
GROUP BY
    client_ip, request_url
ORDER BY
    request_count DESC
LIMIT 10;
```

This tells you which IPs are responsible for the most traffic, and which URLs they are hitting. Sometimes the attack comes from a small number of IPs and you can block them directly in Cloudflare. In our case it was distributed across many IPs, so manual IP blocking was not going to be enough on its own.

Still worth running. It helps you understand the shape of the attack and confirm which endpoints to target with rate limiting.

### 5. Bot Fight Mode

Cloudflare also has **Bot Fight Mode**, which detects and challenges traffic that looks like automated bots using JavaScript fingerprinting. We enabled this as an additional layer.

**Important caveat:** Bot Fight Mode can flag incoming webhooks as bot traffic and block them. We have external services that send webhooks to create leads in our system. When we turned this on, that traffic got disrupted. We ended up creating a rule to skip Bot Fight Mode checks for our webhook API paths.

Know your traffic before you enable this. If you have webhooks or API integrations from third parties, add skip rules for those paths.

### 6. Keep monitoring ALB dashboards

Throughout all of this, we kept two dashboards open:

- Backend ALB: watching request count and instance health
- Webapp ALB: watching request count and response times

Every time we made a change, we watched the graphs to see if it helped. This is how you know if your mitigations are working.

## The cost we could not avoid

Even with everything we did, we paid a price. Because Bot Fight Mode disrupted our webhook traffic, we lost a meaningful volume of lead creation that day. Those are real leads from real external sources that never made it into the system.

The attack did not take us offline, but it hurt. That is the nature of a sustained DDoS. Even a successful defense has side effects.

## The product change that came first

Within a day of the attack being resolved, the first product change we shipped was adding **Cloudflare Turnstile** to the login flow.

Turnstile is Cloudflare's CAPTCHA alternative. It runs a challenge in the background without asking users to click traffic lights or identify crosswalks. For most legitimate users it is invisible. For bots it is a hard stop.

This single change removed the biggest reason we were an easy target. No friction on login meant bots could hammer it all day. With Turnstile, every login attempt has to pass a challenge first. The cost of the attack goes up significantly.

If you are running a web application with a login or signup form and you do not have any bot protection on those endpoints, add it. Do it before you need it.

## What I would do differently

A few things I wish we had already had in place:

**Rate limiting rules already configured.** We had to set these up during the incident, under pressure. Having baseline rules already in place, even loose ones, would have reduced the blast radius immediately.

**A skip rule for webhooks ready to go.** We had to figure out during the incident that Bot Fight Mode was killing our webhook traffic. If we had mapped our critical third party integrations ahead of time, we would have known to add the skip rule from the start.

**CAPTCHA on public facing auth endpoints, with escalating challenge levels.** The most obvious one in hindsight. CAPTCHA is not binary. Most providers let you configure a ladder of challenge levels: silent verification that runs invisibly in the background, a simple puzzle the user solves with one click, and a harder puzzle that requires real effort. Each level adds friction for bots and raises the cost of the attack. Start with silent verification for normal traffic and escalate to harder challenges when traffic looks suspicious. Yes, a harder challenge adds some friction for real users too. But during an active attack, that tradeoff is absolutely worth it. The harder you make each request, the calmer your infrastructure gets.

## If you are reading this during an incident

Here is the short version:

1. Enable Under Attack Mode in Cloudflare.
2. Make sure your DNS is proxied through Cloudflare, not DNS only.
3. Set rate limit rules on the endpoints being hit hardest.
4. Query your access logs to understand which IPs are responsible.
5. Enable Bot Fight Mode, but add skip rules for webhook paths.
6. Keep your ALB dashboards open and watch them after every change.

It is a war of attrition. Stay systematic, keep adjusting, and you will get through it.
