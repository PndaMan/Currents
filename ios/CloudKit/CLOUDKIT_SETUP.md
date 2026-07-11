# CloudKit setup (one-time)

The community features (leaderboards, friends, friend requests, shared spots,
group trips) store data in the **public CloudKit database** of the container
`iCloud.com.aidanmcconnon.currents`. The app talks to CloudKit fine, but
CloudKit needs its **schema** set up before any of it works across devices.

## Why nothing shows up yet

- CloudKit has two environments: **Development** and **Production**.
- **Development** auto-creates record types the first time an Xcode *debug*
  build writes them.
- **Production** (used by **TestFlight and the App Store**) does **not**
  auto-create schema — you must deploy it from Development.
- If you only ever run TestFlight builds, nothing seeds Development, and
  Production has no schema, so every write silently fails and the record types
  never appear. (That's why the Console only shows the system `Users` type.)

The fix is to load the schema once, then deploy it to Production.

## Do this on a computer (the mobile Console can't import schema)

1. Go to <https://icloud.developer.apple.com> → **CloudKit Database** →
   container **iCloud.com.aidanmcconnon.currents**.
2. Top-left environment selector → make sure you're in **Development**.
3. **Schema → Import Schema** and upload **`ios/CloudKit/schema.ckdb`** from this
   repo. That creates all record types with the right fields, a **queryable
   `recordName` index** on each (what makes the app's queries return results),
   and the correct public-database permissions.
4. **Deploy Schema Changes to Production** (button in the Schema area). Confirm.

That's it. TestFlight/App Store builds now read and write the community data.

### If import isn't available, create the types by hand

In **Schema → Record Types → +**, add each type below, then for each one open
its **Indexes** and add a **Queryable** index on **`recordName`**. Finally
**Deploy to Production**.

| Record type   | Fields |
|---------------|--------|
| AnglerProfile | displayName, friendCode, bio, homeWater, region, memberSince, totalCatches, speciesCount, bestWeightKg, bestLengthCm, favoriteSpecies, avatar (Asset), updatedAt |
| LeaderCatch   | anglerName, friendCode, species, weightKg, lengthCm, region, caughtAt, groupCode |
| SharedSpot    | ownerCode, toCode, name, type, notes, lat, lon |
| GroupTrip     | code, name, hostCode, hostName, createdAt |
| GroupMember   | groupCode, memberCode, memberName, joinedAt |
| GroupInvite   | groupCode, tripName, fromCode, fromName, toCode, createdAt |
| FriendRequest | fromCode, fromName, toCode, status, createdAt |
| CatchGrant    | ownerCode, viewerCode |
| CodeClaim     | claimedAt |

Security roles (Console → Security Roles): CloudKit does **not** allow Write for
the `_world` role. `GroupInvite` and `FriendRequest` therefore grant **Write to
`_icloud`** (any signed-in iCloud user) so the recipient can accept/decline a
record the sender created; everything is world-readable. All other types are
creator-write, world-read.

## On the device

- Be **signed into iCloud** (Settings → your name).
- Tap **Join the Community** in Currents. Now sending a friend request, logging
  a catch, etc. writes to the public database and other people can see it.

## To preview the whole experience with no CloudKit at all

Add friend code **`MARLIN`** — a built-in demo angler that's entirely local
(profile, catches, leaderboard, shared spots). Great for checking the UI while
you finish the Console setup.

## Notifications

Friend-request / trip-invite alerts are delivered as a **local notification the
next time the recipient opens the app** (not instant push while it's closed).
Instant background push would require adding the Push Notifications capability
(`aps-environment`) to the App ID + APNs — a separate step.
