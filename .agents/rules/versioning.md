# Versioning Rule for RemindBuddy

Every single time before pushing commits to GitHub (`git push`), you MUST increment the version to the next patch version:
1. `frontend/pubspec.yaml`:
   Increment `version: X.Y.Z+BUILD` to `X.Y.(Z+1)+(BUILD+1)` (e.g. `1.10.14+393`).
2. `frontend/lib/screens/main_screen.dart`:
   Update the drawer/footer version label `'RemindBuddy vX.Y.Z'` to `'RemindBuddy vX.Y.(Z+1)'`.
3. `functions/package.json` & `functions/package-lock.json`:
   Update `"version": "X.Y.Z"` to `"version": "X.Y.(Z+1)"`.
