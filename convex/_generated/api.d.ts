/* eslint-disable */
/**
 * Generated `api` utility.
 *
 * THIS CODE IS AUTOMATICALLY GENERATED.
 *
 * To regenerate, run `npx convex dev`.
 * @module
 */

import type * as admin from "../admin.js";
import type * as auth from "../auth.js";
import type * as blockchain from "../blockchain.js";
import type * as bookings from "../bookings.js";
import type * as driverVehicles from "../driverVehicles.js";
import type * as files from "../files.js";
import type * as http from "../http.js";
import type * as lib_geo from "../lib/geo.js";
import type * as lib_validation from "../lib/validation.js";
import type * as middleware from "../middleware.js";
import type * as mobility from "../mobility.js";
import type * as payments from "../payments.js";
import type * as realEstate from "../realEstate.js";
import type * as rides from "../rides.js";
import type * as seedData from "../seedData.js";
import type * as users from "../users.js";
import type * as vehicleCatalog from "../vehicleCatalog.js";
import type * as verification from "../verification.js";

import type {
  ApiFromModules,
  FilterApi,
  FunctionReference,
} from "convex/server";

declare const fullApi: ApiFromModules<{
  admin: typeof admin;
  auth: typeof auth;
  blockchain: typeof blockchain;
  bookings: typeof bookings;
  driverVehicles: typeof driverVehicles;
  files: typeof files;
  http: typeof http;
  "lib/geo": typeof lib_geo;
  "lib/validation": typeof lib_validation;
  middleware: typeof middleware;
  mobility: typeof mobility;
  payments: typeof payments;
  realEstate: typeof realEstate;
  rides: typeof rides;
  seedData: typeof seedData;
  users: typeof users;
  vehicleCatalog: typeof vehicleCatalog;
  verification: typeof verification;
}>;

/**
 * A utility for referencing Convex functions in your app's public API.
 *
 * Usage:
 * ```js
 * const myFunctionReference = api.myModule.myFunction;
 * ```
 */
export declare const api: FilterApi<
  typeof fullApi,
  FunctionReference<any, "public">
>;

/**
 * A utility for referencing Convex functions in your app's internal API.
 *
 * Usage:
 * ```js
 * const myFunctionReference = internal.myModule.myFunction;
 * ```
 */
export declare const internal: FilterApi<
  typeof fullApi,
  FunctionReference<any, "internal">
>;

export declare const components: {};
