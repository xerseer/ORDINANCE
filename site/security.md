title: Security
description: What the Ordnance server checks on every shot, what it trusts the client with, how lag compensation works, and what it cannot stop.
order: 7
---

# Security

The client shoots; the server decides what happened. This page says exactly what that means, so you know what a cheater can and cannot do.

## The short version {#summary}

A client is trusted with two things, both bounded: **where a shot started**, which must be near the shooter's head and not behind a wall, and **which way it pointed**. Everything else is decided on the server: whether the weapon could fire, where the pellets went, what was hit and how much it hurt.

## Every shot {#checks}

When a shot arrives the server, in order:

1. **Rate-limits the message.** Each player may send at most 60 shot messages a second, before any code runs. Anything beyond is dropped.
2. **Checks the weapon is in their hands** and they are alive.
3. **Runs the weapon's own state machine**: the same code the client used to predict the shot. A weapon that is reloading, cycling, jammed, empty or on Safe cannot fire, whatever the client says. Reload timing gets `Security.ReloadTolerance` of slack for network delay.
4. **Checks the cadence.** An allowance refills at the weapon's rate of fire times `Security.FireRateTolerance`. It absorbs network jitter, but a client cannot fire faster than the weapon on average.
5. **Checks the origin** is within `Security.MaxOriginError` studs of the shooter's head and, with `Security.ValidateLineOfSight`, not on the other side of a wall from it.
6. **Works out the pellets itself** from a seed only the server and that client know. Spread is never sent, so it cannot be removed.
7. **Traces the shot** against the level, and against every other player as they were when the shot was fired (see below).
8. **Applies damage**, after team rules and your [damage handler](api.html#setdamagehandler).

A rejected shot costs the cheater nothing but a correction to their ammo count, and costs the server almost nothing. Turn `Debug.Logger.Level` up to `Debug` to see each rejection and its reason.

## Lag compensation {#lag}

On a network everyone sees everyone else slightly in the past. Without correction you would have to lead every target by your ping.

The server records where every player's body parts were, `Security.SnapshotRate` times a second, for the last second. A hitscan shot is tested against boxes placed where those parts were at the moment the shooter fired: their time, minus half their ping, minus `Security.InterpolationDelay`. It never rewinds more than `Security.MaxRewind` seconds, so a player with a very bad connection does not get to shoot people who have long since reached cover.

Players are never raycast directly; only the rewound boxes are tested. NPCs are hit by the ordinary trace.

> The trade-off every shooter makes: a player with high ping can hit you a moment after you reached cover on your own screen. `MaxRewind` caps how long that moment can be.

## Projectiles {#projectiles}

Projectiles are simulated on the server. The shooter sees their own straight away; the server's copy starts with a head start equal to the time the message took, so both arrive at the same place. Explosions happen on the server, which decides who is in the blast and behind cover.

## What it cannot stop {#limits}

Being honest about this matters more than any feature:

- **Aimbots.** The direction of a shot is the player's to choose. The server makes sure that shot was possible; it cannot tell whether a human aimed it. Detecting inhuman aim is a separate problem, and not one a weapon framework can solve well.
- **Seeing through walls.** Every client is told where every character is, because Roblox replicates characters to everyone. A modified client can draw them through walls.
- **Shots from slightly off the head.** `MaxOriginError` allows for movement and lag, so a cheater can move their origin within that radius. Lower it for slow-moving games.

> Limit: Roblox gives every client every character's position, so no framework can hide players from a modified client. Ordnance makes sure what they do with that information still has to be a shot the weapon could make.
