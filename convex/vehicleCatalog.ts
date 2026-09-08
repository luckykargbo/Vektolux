// convex/vehicleCatalog.ts
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Sierra Leone Vehicle Tier Catalog & Fare Engine
// Centralized transport tier configuration with upfront SLE pricing,
// capacities, 3D asset definitions, and map pin bindings.
// ═══════════════════════════════════════════════════════════════════════

import { query } from "./_generated/server";
import { v } from "convex/values";

export interface VehicleTierDefinition {
  id: string;
  name: string;
  categoryKey: string;
  capacity: number;
  capacityLabel: string;
  render3DUrl: string;
  mapIconSvg: string;
  basePriceSLE: number;
  pricePerKmSLE: number;
  buttonLabel: string;
  description: string;
  etaMinutesDefault: number;
  supportsRide: boolean;
  supportsDelivery: boolean;
}

export const VEHICLE_TIER_CATALOG: VehicleTierDefinition[] = [
  {
    id: "keke_bajaj",
    name: "Keke (Tricycle)",
    categoryKey: "keke",
    capacity: 3,
    capacityLabel: "3 Seats",
    render3DUrl: "https://images.unsplash.com/photo-1558981806-ec527fa84c39?auto=format&fit=crop&w=800&q=80",
    mapIconSvg: "keke",
    basePriceSLE: 15,
    pricePerKmSLE: 5,
    buttonLabel: "Request Keke",
    description: "Swift 3-wheeler tricycle, ideal for Freetown traffic",
    etaMinutesDefault: 3,
    supportsRide: true,
    supportsDelivery: true,
  },
  {
    id: "okada_bike",
    name: "Okada (Motorbike)",
    categoryKey: "okada",
    capacity: 1,
    capacityLabel: "1 Passenger",
    render3DUrl: "https://images.unsplash.com/photo-1558981403-c5f9899a28bc?auto=format&fit=crop&w=800&q=80",
    mapIconSvg: "okada",
    basePriceSLE: 10,
    pricePerKmSLE: 4,
    buttonLabel: "Request Okada",
    description: "Express 2-wheel motorbike for urgent point-to-point transit",
    etaMinutesDefault: 2,
    supportsRide: true,
    supportsDelivery: true,
  },
  {
    id: "car_standard",
    name: "Standard Ride (Taxi)",
    categoryKey: "car",
    capacity: 4,
    capacityLabel: "4 Seats",
    render3DUrl: "https://images.unsplash.com/photo-1549399542-7e3f8b79c341?auto=format&fit=crop&w=800&q=80",
    mapIconSvg: "car",
    basePriceSLE: 30,
    pricePerKmSLE: 8,
    buttonLabel: "Request Standard Ride",
    description: "Comfortable air-conditioned sedan for urban commuting",
    etaMinutesDefault: 5,
    supportsRide: true,
    supportsDelivery: true,
  },
  {
    id: "delivery_van",
    name: "Cargo / Van",
    categoryKey: "van",
    capacity: 2,
    capacityLabel: "2 Seats / 1 Ton Cargo",
    render3DUrl: "https://images.unsplash.com/photo-1586528116311-ad8dd3c8310d?auto=format&fit=crop&w=800&q=80",
    mapIconSvg: "van",
    basePriceSLE: 45,
    pricePerKmSLE: 12,
    buttonLabel: "Request Cargo / Van",
    description: "Commercial van for heavy cargo, freight, and moving",
    etaMinutesDefault: 7,
    supportsRide: false,
    supportsDelivery: true,
  },
];

const vehicleTierValidator = v.object({
  id: v.string(),
  name: v.string(),
  categoryKey: v.string(),
  capacity: v.number(),
  capacityLabel: v.string(),
  render3DUrl: v.string(),
  mapIconSvg: v.string(),
  basePriceSLE: v.number(),
  pricePerKmSLE: v.number(),
  buttonLabel: v.string(),
  description: v.string(),
  etaMinutesDefault: v.number(),
  supportsRide: v.boolean(),
  supportsDelivery: v.boolean(),
});

// ═══════════════════════════════════════════════════════════════════════
//                     GET COMPLETE VEHICLE CATALOG
// ═══════════════════════════════════════════════════════════════════════

export const getVehicleCatalog = query({
  args: {
    serviceType: v.optional(v.string()), // 'ride' | 'delivery'
  },
  returns: v.array(vehicleTierValidator),
  handler: async (_ctx, args) => {
    if (!args.serviceType) {
      return VEHICLE_TIER_CATALOG;
    }
    if (args.serviceType === "delivery") {
      return VEHICLE_TIER_CATALOG.filter((t) => t.supportsDelivery);
    }
    return VEHICLE_TIER_CATALOG.filter((t) => t.supportsRide);
  },
});

// ═══════════════════════════════════════════════════════════════════════
//                     CALCULATE RIDE ESTIMATE
// ═══════════════════════════════════════════════════════════════════════

export const calculateRideEstimate = query({
  args: {
    distanceKm: v.number(),
    serviceType: v.optional(v.string()),
  },
  returns: v.array(
    v.object({
      id: v.string(),
      name: v.string(),
      basePriceSLE: v.number(),
      pricePerKmSLE: v.number(),
      distanceKm: v.number(),
      estimatedFareSLE: v.number(),
      currency: v.string(),
      capacityLabel: v.string(),
      buttonLabel: v.string(),
      etaMinutes: v.number(),
    })
  ),
  handler: async (_ctx, args) => {
    const dist = Math.max(0.1, args.distanceKm);
    const serviceType = args.serviceType ?? "ride";

    const tiers = VEHICLE_TIER_CATALOG.filter((t) =>
      serviceType === "delivery" ? t.supportsDelivery : t.supportsRide
    );

    return tiers.map((tier) => {
      // Upfront Guaranteed Fare: basePrice + (distanceKm * pricePerKm)
      const rawFare = tier.basePriceSLE + dist * tier.pricePerKmSLE;
      // Round to clean SLE currency representation (nearest integer or 0.5)
      const roundedFare = Math.round(rawFare * 2) / 2;

      return {
        id: tier.id,
        name: tier.name,
        basePriceSLE: tier.basePriceSLE,
        pricePerKmSLE: tier.pricePerKmSLE,
        distanceKm: dist,
        estimatedFareSLE: roundedFare,
        currency: "SLE",
        capacityLabel: tier.capacityLabel,
        buttonLabel: tier.buttonLabel,
        etaMinutes: tier.etaMinutesDefault,
      };
    });
  },
});
