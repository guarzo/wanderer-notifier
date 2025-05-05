# Notification Troubleshooting Plan

This document outlines a comprehensive, step-by-step plan to troubleshoot and resolve notification issues after a major refactor.

---

## 1. Understand the Notification Flow

- What triggers each notification? (e.g., system/character added, killmail received)
- What is the expected notification output? (e.g., log, email, webhook, etc.)
- What are the main components involved? (e.g., event emitters, notification service/module, websocket handlers)

---

## 2. Check for Obvious Errors

- **Review logs** for errors or warnings related to notifications.
- **Check for exceptions** in the notification code paths.
- **Look for silent failures** (e.g., try/catch blocks that swallow errors).

---

## 3. Verify Notification Triggers

### a. System/Character Added

- Confirm that the code responsible for adding systems/characters still calls the notification logic.
- Add debug logs or breakpoints to ensure the notification function is invoked.

### b. Killmail Received

- Confirm the websocket handler is still receiving killmail events.
- Ensure the logic that checks for tracked characters/systems is still correct and being called.

---

## 4. Check Notification Dispatch Logic

- Ensure the notification dispatch function is being called with the correct parameters.
- Add debug logs to the entry and exit points of the notification dispatch function.
- If using a queue or async job, ensure jobs are being enqueued and processed.

---

## 5. Check Notification Delivery

- If notifications are sent via external services (email, webhook, etc.), ensure those services are reachable and responding.
- Check for configuration changes (API keys, endpoints, etc.) that may have broken after the refactor.

---

## 6. Test Each Notification Type in Isolation

- Manually trigger each notification type (system added, character added, killmail received).
- Use unit tests or direct function calls to verify the notification logic in isolation.

---

## 7. Review Refactor Changes

- Review the diff/commit history for the refactor, focusing on:
  - Event emission and handling
  - Notification service/module
  - Data models for systems, characters, and killmails
- Look for removed or changed function calls, renamed variables, or altered logic.

---

## 8. Check for Dependency Injection/Registration Issues

- If using dependency injection or service registration, ensure the notification service is still properly registered and injected where needed.

---

## 9. Check for Configuration/Environment Issues

- Ensure all environment variables and configuration files are correct post-refactor.
- Check for missing or changed config keys related to notifications.

---

## 10. Write/Run Automated Tests

- If not already present, write tests for each notification scenario.
- Run the full test suite to catch any missed edge cases.

---

## 11. Document and Fix

- As you find issues, document them and fix them one by one.
- After each fix, re-test the relevant notification flow.

---

## 12. Post-Fix Monitoring

- After resolving, add extra logging/monitoring to notification flows to catch future regressions early.

---

## Summary Table

| Step | What to Check     | How to Check              |
| ---- | ----------------- | ------------------------- |
| 1    | Notification flow | Review code/docs          |
| 2    | Errors            | Logs, error handling      |
| 3    | Triggers          | Debug logs, breakpoints   |
| 4    | Dispatch logic    | Logs, function calls      |
| 5    | Delivery          | Service health, config    |
| 6    | Isolated tests    | Unit tests, manual calls  |
| 7    | Refactor changes  | Code diff, commit history |
| 8    | DI/Registration   | Service registration      |
| 9    | Config/env        | Env vars, config files    |
| 10   | Automated tests   | Write/run tests           |
| 11   | Document/fix      | Track and resolve         |
| 12   | Monitoring        | Add logs/alerts           |
