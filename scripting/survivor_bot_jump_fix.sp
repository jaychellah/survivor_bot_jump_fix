#include <sourcemod>
#include <survivor_bot_blockers_fix>

#define REQUIRE_EXTENSIONS
#include <dhooks>

#define GAMEDATA_FILE	"survivor_bot_jump_fix"

enum struct PlayerLocomotionData
{
	int m_isClimbingUpToLedge;
	int m_landingGoal;
	int m_hasLeftTheGround;
}

PlayerLocomotionData g_PlayerLocomotionData;

DynamicHook hDHook_ILocomotion_ClimbUpToLedge = null;
DynamicHook hDHook_IBody_GetSolidMask = null;

Handle g_hSDKCall_INextBot_GetLocomotionInterface = null;
Handle g_hSDKCall_INextBot_GetBodyInterface = null;
Handle g_hSDKCall_NextBotPlayer_CTerrorPlayer_MyNextBotPointer = null;
Handle g_hSDKCall_ILocomotion_Jump = null;

void ILocomotion_Jump( const int nThis )
{
	SDKCall( g_hSDKCall_ILocomotion_Jump, nThis );
}

Address NextBotPlayer_CTerrorPlayer_MyNextBotPointer( const int iClient )
{
	return SDKCall( g_hSDKCall_NextBotPlayer_CTerrorPlayer_MyNextBotPointer, iClient );
}

Address INextBot_GetLocomotionInterface( const Address adrThis )
{
	return SDKCall( g_hSDKCall_INextBot_GetLocomotionInterface, adrThis );
}

Address INextBot_GetBodyInterface( const Address adrThis )
{
	return SDKCall( g_hSDKCall_INextBot_GetBodyInterface, adrThis );
}

public MRESReturn DHook_PlayerBody_GetSolidMask_Post( int nThis, DHookReturn hReturn )
{
	DHookSetReturn( hReturn, hReturn.Value | CONTENTS_TEAM1 );

	// Don't call real function twice
	return MRES_Supercede;
}

// We're fixing this issue by rewriting this function body without calling IsClimbPossible.
// The game does a raycast to check for climbable ledges, so it's unnecessary to check for a CLIMB_UP discontinuity
// on the path segment (which IsClimbPossible does) when raycast already determines that.
public MRESReturn DHook_PlayerLocomotion_ClimbUpToLedge( int nThis, DHookReturn hReturn, DHookParam hParams )
{
	ILocomotion_Jump( nThis );

	float flVecLandingGoal[3];
	hParams.GetVector( 1, flVecLandingGoal );

	StoreToAddress( view_as< Address >( nThis + g_PlayerLocomotionData.m_isClimbingUpToLedge ), true, NumberType_Int8 );

	StoreToAddress( view_as< Address >( nThis + g_PlayerLocomotionData.m_landingGoal ), 		view_as< int >( flVecLandingGoal[0] ), NumberType_Int32 );
	StoreToAddress( view_as< Address >( nThis + g_PlayerLocomotionData.m_landingGoal + 4 ), 	view_as< int >( flVecLandingGoal[1] ), NumberType_Int32 );
	StoreToAddress( view_as< Address >( nThis + g_PlayerLocomotionData.m_landingGoal + 8 ), 	view_as< int >( flVecLandingGoal[2] ), NumberType_Int32 );

	StoreToAddress( view_as< Address >( nThis + g_PlayerLocomotionData.m_hasLeftTheGround ), 	false, NumberType_Int8 );

	DHookSetReturn( hReturn, true );

	return MRES_Supercede;
}

public void OnClientPutInServer( int iClient )
{
	char szNetClass[32];
	GetEntityNetClass( iClient, szNetClass, sizeof( szNetClass ) );

	if ( StrEqual( szNetClass, "SurvivorBot", true ) )
	{
		Address adrNextBot = NextBotPlayer_CTerrorPlayer_MyNextBotPointer( iClient );

		hDHook_ILocomotion_ClimbUpToLedge.HookRaw( Hook_Pre, INextBot_GetLocomotionInterface( adrNextBot ), DHook_PlayerLocomotion_ClimbUpToLedge );
		hDHook_IBody_GetSolidMask.HookRaw( Hook_Post, INextBot_GetBodyInterface( adrNextBot ), DHook_PlayerBody_GetSolidMask_Post );
	}
}

public void OnPluginStart()
{
	GameData hGameData = new GameData( GAMEDATA_FILE );

	if ( !hGameData )
	{
		SetFailState( "Unable to load gamedata file \"" ... GAMEDATA_FILE ... "\"" );
	}

#define GET_OFFSET_WRAPPER(%0,%1)\
	%0 = hGameData.GetOffset( %1 );\
	\
	if ( %0 == -1 )\
	{\
		delete hGameData;\
		\
		SetFailState( "Unable to find gamedata offset entry for \"" ... %1 ... "\"" );\
	}

#define PREP_SDK_VCALL_SET_FROM_CONF_WRAPPER(%0)\
	if ( !PrepSDKCall_SetFromConf( hGameData, SDKConf_Virtual, %0 ) ) \
	{\
		delete hGameData;\
		\
		SetFailState( "Unable to find gamedata offset entry for \"" ... %0 ... "\"" );\
	}

	int iVtbl_ILocomotion_ClimbUpToLedge;
	GET_OFFSET_WRAPPER(iVtbl_ILocomotion_ClimbUpToLedge, "ILocomotion::ClimbUpToLedge")

	int iVtbl_IBody_GetSolidMask;
	GET_OFFSET_WRAPPER(iVtbl_IBody_GetSolidMask, "IBody::GetSolidMask")

	GET_OFFSET_WRAPPER(g_PlayerLocomotionData.m_isClimbingUpToLedge, "PlayerLocomotion::m_isClimbingUpToLedge")
	GET_OFFSET_WRAPPER(g_PlayerLocomotionData.m_landingGoal, "PlayerLocomotion::m_landingGoal")
	GET_OFFSET_WRAPPER(g_PlayerLocomotionData.m_hasLeftTheGround, "PlayerLocomotion::m_hasLeftTheGround")

	hDHook_ILocomotion_ClimbUpToLedge = new DynamicHook( iVtbl_ILocomotion_ClimbUpToLedge, HookType_Raw, ReturnType_Bool, ThisPointer_Address );
	hDHook_ILocomotion_ClimbUpToLedge.AddParam( HookParamType_VectorPtr );
	hDHook_ILocomotion_ClimbUpToLedge.AddParam( HookParamType_VectorPtr );
	hDHook_ILocomotion_ClimbUpToLedge.AddParam( HookParamType_CBaseEntity );

	hDHook_IBody_GetSolidMask = new DynamicHook( iVtbl_IBody_GetSolidMask, HookType_Raw, ReturnType_Int, ThisPointer_Address );

	StartPrepSDKCall( SDKCall_Raw );
	PREP_SDK_VCALL_SET_FROM_CONF_WRAPPER("INextBot::GetLocomotionInterface")
	PrepSDKCall_SetReturnInfo( SDKType_PlainOldData, SDKPass_Plain );
	g_hSDKCall_INextBot_GetLocomotionInterface = EndPrepSDKCall();

	StartPrepSDKCall( SDKCall_Raw );
	PREP_SDK_VCALL_SET_FROM_CONF_WRAPPER("INextBot::GetBodyInterface")
	PrepSDKCall_SetReturnInfo( SDKType_PlainOldData, SDKPass_Plain );
	g_hSDKCall_INextBot_GetBodyInterface = EndPrepSDKCall();

	StartPrepSDKCall( SDKCall_Player );
	PREP_SDK_VCALL_SET_FROM_CONF_WRAPPER("NextBotPlayer<CTerrorPlayer>::MyNextBotPointer")
	PrepSDKCall_SetReturnInfo( SDKType_PlainOldData, SDKPass_Plain );
	g_hSDKCall_NextBotPlayer_CTerrorPlayer_MyNextBotPointer = EndPrepSDKCall();

	StartPrepSDKCall( SDKCall_Raw );
	PREP_SDK_VCALL_SET_FROM_CONF_WRAPPER("ILocomotion::Jump")
	g_hSDKCall_ILocomotion_Jump = EndPrepSDKCall();

	delete hGameData;

	for ( int iClient = 1; iClient <= MaxClients; iClient++ )
	{
		if ( IsClientInGame( iClient ) )
		{
			OnClientPutInServer( iClient );
		}
	}
}

public Plugin myinfo =
{
	name = "[L4D/2] Survivor Bot Jump Fix",
	author = "Sir Jay",
	description = "Fixes an issue where survivor bots were unable to jump on some ledges/props",
	version = "1.1.0",
	url = "https://github.com/jchellah/survivor_bot_jump_fix"
};