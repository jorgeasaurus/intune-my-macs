Tasks to perform when preparing manifest entries (policies, scripts, apps)

Task 0: Create a structured name
- Format: `IMM - [Short Name]`
- Keep names short, clear, and non-verbose (Title Case)
- Apply the same convention to Policies, Scripts, and Apps

Task 1: Remove the following values from json payloads
- createdDateTime
- lastModifiedDateTime
- id

Task 2: Analyze the artifact and write a brief description
- For Policies:
  - Explain the purpose and functionality
  - Include key settings and compliance requirements where applicable
  - Keep concise (1–2 sentences)
- For Scripts:
  - Summarize what the script does and why
  - Note expected inputs/parameters, outputs, and side effects (e.g., writes files, changes settings)
  - Identify requirements: elevation/root needs, network access, dependencies
  - Keep concise (1–2 sentences + key flags)
- For Packages (PKG installers):
  - Describe what the package installs or configures
  - Note any dependencies or expected management context (e.g., Intune, Jamf, first-run onboarding)
  - Do not add companion .zip files to the manifest; they are for editing/rebuild only

Task 3: Add the artifact to the core manifest.json at the root of the project
- The manifest is read by code to determine what the artifact does and where to find it
- For Policies: count actual settings by searching for unique `settingDefinitionId` values in the JSON
- Use the following JSON structure for the manifest (one object per artifact):

```json
{
  "metadata": {
    "title": "Intune macOS Configuration Policies",
    "description": "Collection of Microsoft Intune configuration policies for macOS device management",
    "version": "1.0",
    "lastUpdated": "YYYY-MM-DD"
  },
  "policies": [
    {
      "type": "[Policy|Script|App|Package]",
      "name": "[Artifact Name]",
      "description": "[Brief description of purpose and function]",
      "platform": "macOS",
      "category": "[Identity|Security|Restrictions|Config]",
      "filePath": "configurations|scripts|apps|onboarding/[subfolder]/[filename]",

      // Policy-only fields
      "settingCount": 0,

      // Script-only fields (omit for Policy/App/Package)
      "runAsSignedInUser": false,
      "hideNotifications": true,
      "frequency": "",
      "maxRetries": 3
    }
  ]
}
```

- Omit fields that are not applicable to the artifact type:
  - Policies: include `settingCount`; omit `requiresElevation`, `runAsSignedInUser`, `hideNotifications`, `frequency`, `maxRetries`
  - Scripts: include `requiresElevation`, plus deployment attributes `runAsSignedInUser`, `hideNotifications`, `frequency` (empty string when not configured), `maxRetries`; omit `settingCount`
  - Apps/Packages: omit both `settingCount` and script fields unless needed
- Omit `isTemplate` unless the file name starts with an underscore (e.g., `_policy.json`) to indicate a template.
- Ignore companion archives (e.g., `.zip`) placed alongside Packages; only reference the signed `.pkg` in the manifest.

Categories to use (choose the best fit):
- Identity: SSO, authentication, sign-in, identity provider integrations (e.g., Entra ID)
- Security: Passcode, encryption (e.g., FileVault), certificates, firewall, threat protections
- Restrictions: Feature/app/device restrictions, access limitations, UI/UX constraints
- Config: General device configuration, preferences, network, system settings


