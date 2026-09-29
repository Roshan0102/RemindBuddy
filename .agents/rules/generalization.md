# Mandatory Generalization Rule for RemindBuddy

### CRITICAL CORE PRINCIPLE: ALWAYS GENERALIZE FOR ALL USERS

1. **Examples are Strictly Test Cases, NOT Custom Targets**:
   - Whenever the user mentions a specific user (e.g. "Roshan"), a specific role (e.g. Cloud & DevOps Engineer), or specific input parameters, this is purely an illustrative example or reproduction case.
   - NEVER write hardcoded checks, specific overrides, or tailored single-user logic for that user.

2. **Universal Architecture Across All Domains & Roles**:
   - Every single feature, Cloud Function, AI prompt, data model, PDF generator, parser, and UI component MUST be completely generic and parameterized.
   - It must work flawlessly for ANY user, in ANY profession or domain (DevOps, Frontend, Backend, Mobile/Flutter, Full-stack, Data/ML, QA, Management, etc.), across ANY experience level (Fresher to Senior/Staff).

3. **Dynamic Configuration Over Hardcoding**:
   - If a behavior needs customization, it must be driven dynamically by the user's Firestore profile/settings or controlled via the Admin panel—NEVER hardcoded in backend or frontend logic.
