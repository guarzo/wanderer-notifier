---
description: "Guidelines for event routing and handling between Phoenix and React. Ensures consistent naming, error handling, and bidirectional communication."
globs:
  - "**/*.{ex,tsx}"
alwaysApply: false
---
# Event Routing Guidelines

- **Naming Conventions:**  
  - Prefix Phoenix events with `phx:` and use clear, descriptive names.
- **Consistency & Cleanup:**  
  - Clearly define event handler functions on both backend and frontend.
  - Ensure proper registration and cleanup (using try/catch and cleanup functions).
- **Bidirectional Communication:**  
  - Use `push_event` in Phoenix to send updates; React should listen via hooks.
- **Error Handling:**  
  - Implement error logging and fallback logic to catch any issues.
- **Reference:**  
  - See @notes/architecture.md for an overview of the event system.
