---@class ServerFramework
---@field getPlayerFromId fun(self: ServerFramework, source: number): table
---@field getIdentifier fun(self: ServerFramework, source: number): string
---@field getAccountMoney fun(self: ServerFramework, source: number, account: MoneyType): number
---@field removeAccountMoney fun(self: ServerFramework, source: number, account: MoneyType, amount: number): boolean
---@field addAccountMoney fun(self: ServerFramework, source: number, account: MoneyType, amount: number)
---@field removeItem fun(self: ServerFramework, source: number, item: string, count: number)
---@field playerIsAdmin fun(self: ServerFramework, source: number): boolean
---@field getUserName fun(self: ServerFramework, source: number): string, string
---@field registerUsableItem fun(self: ServerFramework, item: string, cb: function)
---@field getSourceFromIdentifier fun(self: ServerFramework, identifier: string): number
---@field getItem fun(self: ServerFramework, source: number, item: string): {count: number}
---@field addItem fun(self: ServerFramework, source: number, item: string, count: number, slot?: number | false, info?: table): boolean
---@field getUserNameFromIdentifier fun(self: ServerFramework, identifier: string): string
---@field getJobName fun(self: ServerFramework, source: number): string
---@field getJobGrade fun(self: ServerFramework, source: number): number
---@field getPlayers fun(self: ServerFramework): table
---@field getInventory fun(self: ServerFramework, source: number): table
---@field getItemList fun(self: ServerFramework): table
---@field getJobsData fun(self: ServerFramework): Job[]
---@field searchPlayers fun(self: ServerFramework, query: string): table
---@field setHouseInside fun(self: ServerFramework, source: number, insideId: number)
---@field getHouseInside fun(self: ServerFramework, source: number): number
---@field getMeta fun(self: ServerFramework, source: number): table

---@class ClientFramework
---@field getPlayerData fun(self: ClientFramework): table
---@field getIdentifier fun(self: ClientFramework): string
---@field getJobName fun(self: ClientFramework): string
---@field getJobGrade fun(self: ClientFramework): number
---@field getPlayers fun(self: ClientFramework): table
---@field getObject fun(self: ClientFramework): table

---@class Job
---@field name string
---@field label string
---@field grades {label: string, grade: number}

---@class Gang
---@field name string
---@field label string
---@field grades {label: string, grade: number}

---@alias MoneyType 'money' | 'bank' | 'black_money'

---@class CreatorItem
---@field name string
---@field label string
---@field image string

---@class Blip
---@field enable boolean
---@field coords vector3
---@field label string
---@field sprite number
---@field color number
---@field scale number

---@class ClosestPlayer
---@field id number
---@field name string

---@class OrganizationOwner
---@field identifier string
---@field name string

---@class OrganizationInteriorData
---@field tier number
---@field coords vector4
---@field exit vector4

---@class MLODoor
---@field coords vector4
---@field [string] any

---@class OrganizationMLOData
---@field doors MLODoor[]
---@field test_coords vector4

---@class OrganizationIPLData
---@field exit vector3
---@field tier number
---@field themeId string

---@class OrganizationRankPermissions
---@field canAccessWardrobe? boolean
---@field canAccessStash? boolean
---@field canAccessCharge? boolean
---@field canManageMembers? boolean
---@field canManageFinance? boolean
---@field canManageRanks? boolean
---@field canSetLocations? boolean
---@field canBuyUpgrades? boolean
---@field canAccessBossMenu? boolean
---@field canAccessMembers? boolean
---@field canAccessRanks? boolean
---@field canAccessFinance? boolean
---@field canAccessGarage? boolean
---@field canAccessVehicleStore? boolean
---@field canAccessUpgradeInterior? boolean
---@field canAccessManagement? boolean

---@class OrganizationRank
---@field id number
---@field organization_id number
---@field label string
---@field permissions? OrganizationRankPermissions

---@class OrganizationMember
---@field id number
---@field organization_id number
---@field identifier string
---@field name string
---@field rank_id? number
---@field is_boss? boolean
---@field joined_at? string
---@field rank? OrganizationRank

---@class Organization
---@field id number
---@field label string
---@field owner? OrganizationOwner
---@field color string
---@field entry_coords? vector4
---@field garage_coords? vector4
---@field type 'shell' | 'mlo' | 'ipl'
---@field interior_data? OrganizationInteriorData
---@field ipl_data? OrganizationIPLData
---@field mlo_data? OrganizationMLOData
---@field creator? string
---@field created_at? string
---@field updated_at? string
---@field members OrganizationMember[]
---@field ranks OrganizationRank[]

---@class TerritoryData
---@field points vector3[]
---@field thickness number
---@field width number
---@field topPoint vector3
---@field bottomPoint vector3

---@class Territory
---@field id number
---@field label string
---@field organization_id? number
---@field organization? Organization
---@field zone TerritoryData
---@field color? string
---@field creator? string
---@field created_at? string
---@field updated_at? string

---@class SeasonPassData
---@field id number
---@field price number
---@field endDate string
---@field rewards table[]
---@field creator? string
---@field created_at? string
---@field updated_at? string

---@class InteractionData
---@field icon string
---@field title string
---@field onSelect? function

---@class UpdateObject
---@field coords? string
---@field rotation? string
---@field inStash? boolean

---@alias GizmoMode 'gizmo' | 'mgizmo'

---@class DecorationObject
---@field id number
---@field modelName string
---@field coords vector3
---@field rotation vector3
---@field handle number
---@field inStash boolean
---@field spawned? boolean
---@field created string | osdate
---@field house string
---@field inHouse boolean
---@field uniq? string -- Backward compatibility
---@field lightData? Light

---@class Light
---@field name string
---@field color number
---@field rgb string
---@field intensity number
---@field active boolean

---@class PvpBattleData
---@field id number
---@field label string
---@field start_date string
---@field duration number
---@field zone_points table
---@field center_coords vector3
---@field rewards table[]
---@field allowed_organizations table[]
---@field status string
---@field creator string
---@field created_at string
---@field updated_at string

---@class PvpReward
---@field id string
---@field label string
---@field type string
---@field value number
---@field rarity string
---@field moneyType string
---@field moneyAmount number
---@field vehicleModel string
---@field itemName string
---@field itemAmount number
