using UnrealBuildTool;

public class MmoKitClientEditorTarget : TargetRules
{
    public MmoKitClientEditorTarget(TargetInfo Target) : base(Target)
    {
        Type = TargetType.Editor;
        DefaultBuildSettings = BuildSettingsVersion.Latest;
        IncludeOrderVersion = EngineIncludeOrderVersion.Latest;
        ExtraModuleNames.Add("MmoKitClient");
    }
}
