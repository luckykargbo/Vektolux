import { v } from "convex/values";
import { mutation, query } from "./_generated/server";
import { Id } from "./_generated/dataModel";
import { isListingPublic, toPublicProperty, toPublicVehicle } from "./lib/publicListing";
import { requireSelf } from "./lib/auth";

export const toggleFollow = mutation({
  args: {
    currentUserId: v.id("users"),
    targetUserId: v.id("users"),
    sessionToken: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    const { user } = await requireSelf(ctx, args.sessionToken, args.currentUserId);

    if (args.currentUserId === args.targetUserId) {
      throw new Error("Cannot follow yourself");
    }

    const targetUser = await ctx.db.get(args.targetUserId);
    if (!targetUser) throw new Error("Target user not found");

    const existingFollow = await ctx.db
      .query("follows")
      .withIndex("by_follower_following", (q) =>
        q.eq("followerId", args.currentUserId).eq("followingId", args.targetUserId)
      )
      .first();

    if (existingFollow) {
      await ctx.db.delete(existingFollow._id);
      
      const newFollowingCount = Math.max(0, (user.followingCount || 0) - 1);
      const newFollowersCount = Math.max(0, (targetUser.followersCount || 0) - 1);
      
      await ctx.db.patch(user._id, { followingCount: newFollowingCount });
      await ctx.db.patch(targetUser._id, { followersCount: newFollowersCount });
      
      return { isFollowing: false };
    } else {
      await ctx.db.insert("follows", {
        followerId: args.currentUserId,
        followingId: args.targetUserId,
        createdAt: Date.now(),
      });
      // A real event for the person being followed (unfollowing sends nothing).
      await ctx.db.insert("user_notifications", {
        userId: args.targetUserId as string,
        targetType: "single_user",
        title: "New follower",
        body: `${user.name} started following you.`,
        deepLinkScreen: "followers",
        deepLinkId: args.currentUserId as string,
        read: false,
        createdAt: Date.now(),
      });
      
      const newFollowingCount = (user.followingCount || 0) + 1;
      const newFollowersCount = (targetUser.followersCount || 0) + 1;
      
      await ctx.db.patch(user._id, { followingCount: newFollowingCount });
      await ctx.db.patch(targetUser._id, { followersCount: newFollowersCount });
      
      return { isFollowing: true };
    }
  },
});

export const getFollowStatus = query({
  args: {
    currentUserId: v.id("users"),
    targetUserId: v.id("users"),
  },
  handler: async (ctx, args) => {
    const existingFollow = await ctx.db
      .query("follows")
      .withIndex("by_follower_following", (q) =>
        q.eq("followerId", args.currentUserId).eq("followingId", args.targetUserId)
      )
      .first();
      
    return { isFollowing: !!existingFollow };
  },
});

export const getFollowersList = query({
  args: { userId: v.id("users") },
  handler: async (ctx, args) => {
    const follows = await ctx.db
      .query("follows")
      .withIndex("by_following", (q) => q.eq("followingId", args.userId))
      .order("desc")
      .take(50);
      
    const followers = [];
    for (const follow of follows) {
      const user = await ctx.db.get(follow.followerId);
      if (user) {
        followers.push({
          _id: user._id,
          name: user.name,
          avatarUrl: user.avatarUrl,
          verificationBadge: user.verificationBadge,
        });
      }
    }
    
    return followers;
  },
});

export const getFollowingList = query({
  args: { userId: v.id("users") },
  handler: async (ctx, args) => {
    const follows = await ctx.db
      .query("follows")
      .withIndex("by_follower", (q) => q.eq("followerId", args.userId))
      .order("desc")
      .take(50);
      
    const following = [];
    for (const follow of follows) {
      const user = await ctx.db.get(follow.followingId);
      if (user) {
        following.push({
          _id: user._id,
          name: user.name,
          avatarUrl: user.avatarUrl,
          verificationBadge: user.verificationBadge,
        });
      }
    }
    
    return following;
  },
});

export const getSocialFeed = query({
  args: { userId: v.id("users") },
  handler: async (ctx, args) => {
    // Collect all follow records - if it gets too large we'd need a different approach,
    // but for now .collect() on a bounded number of follows is necessary since we
    // need to query across multiple owners.
    const follows = await ctx.db
      .query("follows")
      .withIndex("by_follower", (q) => q.eq("followerId", args.userId))
      .take(500); // Bounded to prevent unbounded read
      
    const followingIds = follows.map(f => f.followingId);
    if (followingIds.length === 0) return [];
    
    let allListings: any[] = [];
    
    for (const ownerId of followingIds) {
      const realEstate = await ctx.db
        .query("realEstateListings")
        .withIndex("by_owner", (q) => q.eq("ownerId", ownerId))
        .filter((q) => q.eq(q.field("isPublished"), true))
        .order("desc")
        .take(10);
        
      for (const item of realEstate) {
        if (!isListingPublic(item)) continue; // not under review, rejected, archived or removed
        // Privacy Guard: Strip phone fields from public feed
        const { privateContactPhone: _p, contactPhone: _c, ...safeItem } =
          item as typeof item & { privateContactPhone?: string; contactPhone?: string };
        allListings.push({ ...toPublicProperty(safeItem), type: "property" });
      }
      
      const vehicles = await ctx.db
        .query("vehicleListings")
        .withIndex("by_owner", (q) => q.eq("ownerId", ownerId))
        .filter((q) => q.eq(q.field("isPublished"), true))
        .order("desc")
        .take(10);
        
      for (const item of vehicles) {
        // Privacy Guard: Strip phone fields from public feed
        const { privateContactPhone: _p, contactPhone: _c, ...safeItem } =
          item as typeof item & { privateContactPhone?: string; contactPhone?: string };
        allListings.push({ ...toPublicVehicle(safeItem), type: "vehicle" });
      }
    }
    
    allListings.sort((a, b) => b._creationTime - a._creationTime);
    return allListings.slice(0, 30);
  },
});
