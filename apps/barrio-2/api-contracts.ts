/** Shared integration contract for the future BARRIO backend. No browser credentials belong here. */
export type SourceKind = 'official' | 'barrio' | 'demo';
export interface Tianguis { id:string; name:string; coordinates:[number,number]; alcaldia?:string; neighborhood?:string; operatingDays?:string[]; hours?:string; source:SourceKind; sourceMetadata:Record<string,unknown> }
export interface Product { id:string; merchantId:string; name:string; category:string; price?:number; unit?:string; available?:boolean }
export interface Merchant { id:string; name:string; businessName:string; tianguisId?:string; categories:string[]; whatsappUrl?:string; profileCompletion:number; source:SourceKind }
export interface InventorySnapshot { id:string; merchantId:string; capturedAt:string; products:Array<{productId?:string; name:string; quantity:number; unit:string; manuallyCorrected:boolean}>; source:'external-analysis'|'manual'|'demo' }
export interface Offer { id:string; merchantId:string; title:string; description?:string; validUntil?:string; source:SourceKind }
export interface CitySummary { official:{tianguisCount:number; activeByDay:Record<string,number>}; barrio:{registeredMerchants:number; processedSnapshots:number; publishedOffers:number; source:'live'|'demo'} }

/** GET /api/tianguis · /merchants · /merchants/:id · /merchants/:id/inventory · /products · /offers · /city/summary */
export interface BarrioAdapter { getTianguis():Promise<Tianguis[]>; getMerchants():Promise<Merchant[]>; getMerchant(id:string):Promise<Merchant>; getInventory(merchantId:string):Promise<InventorySnapshot[]>; getProducts():Promise<Product[]>; getOffers():Promise<Offer[]>; getCitySummary():Promise<CitySummary> }
