/* eslint-disable */
/**
 * Generated `api` utility.
 *
 * THIS CODE IS AUTOMATICALLY GENERATED.
 *
 * To regenerate, run `npx convex dev`.
 * @module
 */

import type * as adminFinance from "../adminFinance.js";
import type * as admin from "../admin.js";
import type * as adminPortal from "../adminPortal.js";
import type * as agentVerification from "../agentVerification.js";
import type * as auth from "../auth.js";
import type * as blockchain from "../blockchain.js";
import type * as bookings from "../bookings.js";
import type * as businessVerification from "../businessVerification.js";
import type * as emails from "../emails.js";
import type * as escrow from "../escrow.js";
import type * as explore from "../explore.js";
import type * as files from "../files.js";
import type * as hotelBookings from "../hotelBookings.js";
import type * as hotels from "../hotels.js";
import type * as hotelVerification from "../hotelVerification.js";
import type * as locations from "../locations.js";
import type * as crons from "../crons.js";
import type * as http from "../http.js";
import type * as lib_auth from "../lib/auth.js";
import type * as lib_geo from "../lib/geo.js";
import type * as lib_oauth from "../lib/oauth.js";
import type * as lib_publicListing from "../lib/publicListing.js";
import type * as lib_rateLimit from "../lib/rateLimit.js";
import type * as lib_session from "../lib/session.js";
import type * as lib_slLocations from "../lib/slLocations.js";
import type * as lib_paymentErrors from "../lib/paymentErrors.js";
import type * as lib_pin from "../lib/pin.js";
import type * as lib_validation from "../lib/validation.js";
import type * as middleware from "../middleware.js";
import type * as mobility from "../mobility.js";
import type * as notifications from "../notifications.js";
import type * as payments from "../payments.js";
import type * as qrPayment from "../qrPayment.js";
import type * as realEstate from "../realEstate.js";
import type * as realEstateEscrow from "../realEstateEscrow.js";
import type * as roles from "../roles.js";
import type * as feeRules from "../feeRules.js";
import type * as listingAgents from "../listingAgents.js";
import type * as reversals from "../reversals.js";
import type * as monimeWebhooks from "../monimeWebhooks.js";
import type * as seedData from "../seedData.js";
import type * as social from "../social.js";
import type * as subscriptions from "../subscriptions.js";
import type * as users from "../users.js";
import type * as verification from "../verification.js";
import type * as wallet from "../wallet.js";
import type * as walletCore from "../walletCore.js";
import type * as wallets from "../wallets.js";
import type * as withdrawals from "../withdrawals.js";

import type {
  ApiFromModules,
  FilterApi,
  FunctionReference,
} from "convex/server";

declare const fullApi: ApiFromModules<{
  adminFinance: typeof adminFinance;
  admin: typeof admin;
  adminPortal: typeof adminPortal;
  agentVerification: typeof agentVerification;
  auth: typeof auth;
  blockchain: typeof blockchain;
  bookings: typeof bookings;
  businessVerification: typeof businessVerification;
  emails: typeof emails;
  escrow: typeof escrow;
  explore: typeof explore;
  files: typeof files;
  hotelBookings: typeof hotelBookings;
  hotels: typeof hotels;
  hotelVerification: typeof hotelVerification;
  locations: typeof locations;
  crons: typeof crons;
  http: typeof http;
  "lib/auth": typeof lib_auth;
  "lib/geo": typeof lib_geo;
  "lib/oauth": typeof lib_oauth;
  "lib/publicListing": typeof lib_publicListing;
  "lib/rateLimit": typeof lib_rateLimit;
  "lib/session": typeof lib_session;
  "lib/slLocations": typeof lib_slLocations;
  "lib/paymentErrors": typeof lib_paymentErrors;
  "lib/pin": typeof lib_pin;
  "lib/validation": typeof lib_validation;
  middleware: typeof middleware;
  mobility: typeof mobility;
  notifications: typeof notifications;
  payments: typeof payments;
  qrPayment: typeof qrPayment;
  realEstate: typeof realEstate;
  realEstateEscrow: typeof realEstateEscrow;
  roles: typeof roles;
  feeRules: typeof feeRules;
  listingAgents: typeof listingAgents;
  reversals: typeof reversals;
  monimeWebhooks: typeof monimeWebhooks;
  seedData: typeof seedData;
  social: typeof social;
  subscriptions: typeof subscriptions;
  users: typeof users;
  verification: typeof verification;
  wallet: typeof wallet;
  walletCore: typeof walletCore;
  wallets: typeof wallets;
  withdrawals: typeof withdrawals;
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
