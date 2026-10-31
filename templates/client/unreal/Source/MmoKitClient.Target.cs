using UnrealBuildTool;

public class MmoKitClientTarget : TargetRules
{
    public MmoKitClientTarget(TargetInfo Target) : base(Target)
    {
        Type = TargetType.Game;
        DefaultBuildSettings = BuildSettingsVersion.Latest;
        IncludeOrderVersion = EngineIncludeOrderVersion.Latest;
        ExtraModuleNames.Add("MmoKitClient");
    }
}
