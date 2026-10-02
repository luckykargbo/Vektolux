// convex/locations.ts
// Public reference data: Sierra Leone regions -> districts -> towns, for the app's location pickers
// (registration, listing creation, search filters). Contains no user data.
import { query } from "./_generated/server";
import { v } from "convex/values";
import { SL_DISTRICTS } from "./lib/slLocations";

export const getSierraLeoneLocations = query({
  args: {},
  returns: v.array(
    v.object({ region: v.string(), district: v.string(), towns: v.array(v.string()) })
  ),
  handler: async () =>
    SL_DISTRICTS.map((d) => ({ region: d.region, district: d.district, towns: [...d.towns] })),
});
