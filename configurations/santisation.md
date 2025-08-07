Tasks to perform when sanitizing json policy 

Task 1: Remove the following values from json payloads
- createdDateTime
- lastModifiedDateTime
- id

Task 2: Analyze policy and write brief description in description key
- Description should explain the purpose and functionality of the policy
- Include key settings and compliance requirements where applicable
- Keep descriptions concise but informative (1-2 sentences)

Task 3: Add policy to core manifest.xml at root of project
- manifest will be read by code to determine what the policy does and where to find it
- Count actual settings by searching for unique "settingDefinitionId" values in the JSON
- Use the following XML structure for each policy:

```xml
<policy>
    <name>[Policy Name from JSON]</name>
    <description>[Brief description of policy purpose and function]</description>
    <platform>macOS</platform>
    <category>[Authentication|Security|Encryption|Compliance|Other]</category>
    <technology>mdm,appleRemoteManagement</technology>
    <filePath>configurations/[subfolder]/[filename.json]</filePath>
    <settingCount>[Count of unique settingDefinitionId values]</settingCount>
</policy>
```

Categories to use:
- Authentication: SSO, identity, login policies
- Security: Passcode, access control, device restrictions
- Encryption: FileVault, disk encryption, data protection
- Compliance: Device compliance, monitoring policies
- Other: Miscellaneous or multi-category policies


