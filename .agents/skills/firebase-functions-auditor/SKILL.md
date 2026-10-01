---
name: firebase-functions-auditor
description: >-
  Use this skill whenever authoring, updating, or debugging Firebase Cloud Functions (v2), Firestore triggers, schedulers, or GCP billing integrations in RemindBuddy.
---

# Firebase Functions & Cloud Architecture Auditor for RemindBuddy

This skill provides operational procedures and architectural checklists for developing resilient, cost-effective, and performant Firebase Cloud Functions (v2) in RemindBuddy.

---

## 1. Cloud Functions Gen 2 Standard Configuration

* **Runtime Parameters**:
  * Set explicit `memory`, `timeoutSeconds`, and `maxInstances` on every function to prevent runaway scaling and billing surprises:
    ```typescript
    import { onCall, onRequest, HttpsError } from "firebase-functions/v2/https";
    import { onSchedule } from "firebase-functions/v2/scheduler";

    export const myFunction = onCall({
      region: "asia-south1", // Consistent region across all functions
      memory: "256MiB",
      timeoutSeconds: 60,
      maxInstances: 10,
    }, async (request) => {
      // Logic
    });
    ```
* **Cold Start & Concurrency Optimization**:
  * Keep heavy initializations (Firebase Admin SDK, Gemini SDK, external API clients) at the module top level, outside the function handler.
  * Lazy-load modules only if they are heavy and rarely invoked.

---

## 2. Firestore Access & Data Integrity

* **Batches and Bulk Writes**:
  * Never execute unbound loops of `await docRef.set()` or `await docRef.update()`.
  * Chunk writes into batches of up to 450 (safe margin under Firestore's 500-write limit):
    ```typescript
    const chunks = chunkArray(items, 450);
    for (const chunk of chunks) {
      const batch = db.batch();
      for (const item of chunk) {
        batch.set(db.collection('target').doc(item.id), item);
      }
      await batch.commit();
    }
    ```
* **Transaction Safety**:
  * For balance updates (finance transactions, gold chit payments, budget deductions), always use `db.runTransaction()` to prevent race conditions.

---

## 3. GCP Billing & Infinite Loop Prevention

* **Trigger Guards**:
  * In `onDocumentWritten` or `onDocumentUpdated` triggers, always verify that the field being changed was not updated by the function itself to prevent recursive execution loops:
    ```typescript
    const beforeData = event.data?.before.data();
    const afterData = event.data?.after.data();

    // Guard against self-triggering updates:
    if (beforeData?.updatedByFunction === afterData?.updatedByFunction) {
      return;
    }
    ```
* **Billing Alerts & Quotas**:
  * Ensure alerts from [`functions/src/modules/admin/gcpBilling.ts`](file:///home/roshan-axcess/Documents/RemindBuddy/functions/src/modules/admin/gcpBilling.ts) remain intact and are not bypassed.

---

## 4. Structured Logging & Telemetry

* Always import and use the centralized logger from [`functions/src/utils/logger.ts`](file:///home/roshan-axcess/Documents/RemindBuddy/functions/src/utils/logger.ts):
  ```typescript
  import { logger } from "../utils/logger";

  logger.info("Executing shift reminder job", { uid, shiftDate });
  logger.error("Failed to parse SMS transaction", error, { rawLength: rawText.length });
  ```
* Never use raw `console.log` for sensitive data or production payloads.
