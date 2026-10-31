using UnrealBuildTool;

public class MmoKitClient : ModuleRules
{
    public MmoKitClient(ReadOnlyTargetRules Target) : base(Target)
    {
        PCHUsage = PCHUsageMode.UseExplicitOrSharedPCHs;
        PublicDependencyModuleNames.AddRange(new string[] { "Core", "CoreUObject", "Engine", "InputCore", "SpacetimeDbSdk" });
    }
}
