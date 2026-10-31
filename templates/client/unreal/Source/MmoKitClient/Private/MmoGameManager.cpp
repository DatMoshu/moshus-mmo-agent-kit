#include "MmoGameManager.h"
#include "Connection/Credentials.h"
#include "Engine/World.h"
#include "GameFramework/PlayerController.h"
#include "InputCoreTypes.h"

AMmoGameManager::AMmoGameManager()
{
    PrimaryActorTick.bCanEverTick = true;
    PrimaryActorTick.bStartWithTickEnabled = true;
}

void AMmoGameManager::BeginPlay()
{
    Super::BeginPlay();
    if (PlayerName.IsEmpty()) PlayerName = FString::Printf(TEXT("unreal-%d"), FMath::RandRange(1000, 9999));

    FOnConnectDelegate OnConnect;
    BIND_DELEGATE_SAFE(OnConnect, this, AMmoGameManager, HandleConnect);
    FOnDisconnectDelegate OnDisconnect;
    BIND_DELEGATE_SAFE(OnDisconnect, this, AMmoGameManager, HandleDisconnect);
    FOnConnectErrorDelegate OnError;
    BIND_DELEGATE_SAFE(OnError, this, AMmoGameManager, HandleConnectError);

    // The saved token IS the player's identity. Dev only; use OIDC (e.g. SpacetimeAuth) in production.
    UCredentials::Init(TEXT(".mmo_kit_token"));
    const FString Token = UCredentials::LoadToken();

    UDbConnectionBuilder* Builder = UDbConnection::Builder()
        ->WithUri(ServerUri)
        ->WithDatabaseName(DatabaseName)
        ->OnConnect(OnConnect)
        ->OnDisconnect(OnDisconnect)
        ->OnConnectError(OnError);
    if (!Token.IsEmpty()) Builder->WithToken(Token);
    Conn = Builder->Build();

    // Register row callbacks once, before the first FrameTick.
    Conn->Db->EntityTransform->OnInsert.AddDynamic(this, &AMmoGameManager::HandleTransformInsert);
    Conn->Db->EntityTransform->OnUpdate.AddDynamic(this, &AMmoGameManager::HandleTransformUpdate);
    Conn->Db->EntityTransform->OnDelete.AddDynamic(this, &AMmoGameManager::HandleTransformDelete);
}

void AMmoGameManager::EndPlay(const EEndPlayReason::Type EndPlayReason)
{
    if (Conn) { Conn->Disconnect(); Conn = nullptr; }
    Super::EndPlay(EndPlayReason);
}

void AMmoGameManager::HandleConnect(UDbConnection* InConn, FSpacetimeDBIdentity Identity, const FString& Token)
{
    MyHex = Identity.ToHex();
    UCredentials::SaveToken(Token);
    UE_LOG(LogTemp, Log, TEXT("MMO: connected as %s"), *MyHex);

    FOnSubscriptionApplied Applied;
    BIND_DELEGATE_SAFE(Applied, this, AMmoGameManager, HandleApplied);
    // Thin starter: whole world. Big worlds: subscribe to 3x3 AOI cells (recipes/aoi-subscriptions.md).
    TArray<FString> Queries = {
        TEXT("SELECT * FROM world_config"),
        TEXT("SELECT * FROM tick_health"),
        TEXT("SELECT * FROM player"),
        TEXT("SELECT * FROM entity_transform"),
    };
    Conn->SubscriptionBuilder()->OnApplied(Applied)->Subscribe(Queries);
}

void AMmoGameManager::HandleApplied(FSubscriptionEventContext Context)
{
    Conn->Reducers->Join(PlayerName);
}

void AMmoGameManager::HandleConnectError(const FString& Error)
{
    UE_LOG(LogTemp, Error, TEXT("MMO: connect error: %s"), *Error);
}

void AMmoGameManager::HandleDisconnect(UDbConnection* InConn, const FString& Error)
{
    UE_LOG(LogTemp, Warning, TEXT("MMO: disconnected: %s"), *Error);
    bJoined = false;
}

void AMmoGameManager::HandleTransformInsert(const FEventContext& Context, const FEntityTransformType& NewRow) { Upsert(NewRow); }
void AMmoGameManager::HandleTransformUpdate(const FEventContext& Context, const FEntityTransformType& OldRow, const FEntityTransformType& NewRow) { Upsert(NewRow); }

void AMmoGameManager::HandleTransformDelete(const FEventContext& Context, const FEntityTransformType& DeletedRow)
{
    FEntityView View;
    if (Entities.RemoveAndCopyValue(DeletedRow.Identity.ToHex(), View) && View.Actor.IsValid())
    {
        View.Actor->Destroy();
    }
}

void AMmoGameManager::Upsert(const FEntityTransformType& Row)
{
    const FString Hex = Row.Identity.ToHex();
    // World (x, y) maps to Unreal (X, Y) on the ground plane.
    const FVector Target(Row.X * UnitsPerWorldUnit, Row.Y * UnitsPerWorldUnit, 0.f);
    if (Hex == MyHex) bJoined = true; // the server creates our transform row on join
    if (FEntityView* View = Entities.Find(Hex))
    {
        View->Target = Target;
        return;
    }
    UClass* Cls = EntityClass ? EntityClass.Get() : AActor::StaticClass();
    AActor* Spawned = GetWorld()->SpawnActor<AActor>(Cls, Target, FRotator::ZeroRotator);
    Entities.Add(Hex, FEntityView{ Spawned, Target });
}

void AMmoGameManager::SendIntent()
{
    APlayerController* PC = GetWorld() ? GetWorld()->GetFirstPlayerController() : nullptr;
    if (!PC || !bJoined) return;
    const int8 Dx = (PC->IsInputKeyDown(EKeys::D) ? 1 : 0) - (PC->IsInputKeyDown(EKeys::A) ? 1 : 0);
    const int8 Dy = (PC->IsInputKeyDown(EKeys::W) ? 1 : 0) - (PC->IsInputKeyDown(EKeys::S) ? 1 : 0);
    if (Dx == LastDx && Dy == LastDy) return; // send intent only when it changes
    LastDx = Dx; LastDy = Dy;
    Conn->Reducers->SetInput(Dx, Dy, ++Seq);
}

void AMmoGameManager::Tick(float DeltaTime)
{
    Super::Tick(DeltaTime);
    if (Conn && Conn->IsActive()) Conn->FrameTick();
    SendIntent();
    const float K = 1.f - FMath::Exp(-Smoothing * DeltaTime);
    for (auto& Pair : Entities)
    {
        if (AActor* A = Pair.Value.Actor.Get())
        {
            A->SetActorLocation(FMath::Lerp(A->GetActorLocation(), Pair.Value.Target, K));
        }
    }
}
