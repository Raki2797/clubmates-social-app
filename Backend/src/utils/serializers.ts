export type UserRow = {
  id: string;
  phone_e164?: string;
  name: string;
  age: number;
  bio: string | null;
  profession: string | null;
  gender: string | null;
  height: number | null;
  interests: string[] | null;
  is_verified: boolean;
  is_ghost_mode?: boolean | null;
  profile_completed?: boolean;
  verification_selfie_url?: string | null;
  verification_failure_reason?: string | null;
  verification_mismatched_photo_ids?: string[] | null;
  looking_for?: string | null;
  pref_age_min?: number | null;
  pref_age_max?: number | null;
  pref_genders?: string[] | null;
  pref_height_min?: number | null;
  pref_height_max?: number | null;
  pref_verified_only?: boolean | null;
  notif_enabled?: boolean | null;
  notif_new_match?: boolean | null;
  notif_new_message?: boolean | null;
  notif_liked_you?: boolean | null;
  notif_super_like?: boolean | null;
  notif_venue_activity?: boolean | null;
};

export type PromptRow = {
  id: string;
  question: string;
  answer: string;
  position: number;
};

export type PhotoRow = {
  id: string;
  storage_key: string;
  cdn_url: string;
  position: number;
};

export function serializeProfile(
  user: UserRow,
  prompts: PromptRow[] = [],
  photos: PhotoRow[] = []
) {
  return {
    id: user.id,
    phone: user.phone_e164,
    name: user.name,
    age: user.age,
    bio: user.bio ?? "",
    profession: user.profession ?? "",
    gender: user.gender ?? "",
    height: user.height ?? 0,
    interests: user.interests ?? [],
    isVerified: user.is_verified,
    isGhostMode: user.is_ghost_mode ?? false,
    profileCompleted: user.profile_completed ?? true,
    verificationSelfieUrl: user.verification_selfie_url ?? null,
    verificationFailureReason: user.verification_failure_reason ?? null,
    verificationMismatchedPhotoIds: user.verification_mismatched_photo_ids ?? [],
    lookingFor: user.looking_for ?? "",
    preferences: {
      ageMin: user.pref_age_min ?? 18,
      ageMax: user.pref_age_max ?? 60,
      genders: user.pref_genders ?? [],
      heightMin: user.pref_height_min ?? 140,
      heightMax: user.pref_height_max ?? 220,
      verifiedOnly: user.pref_verified_only ?? false
    },
    notificationPreferences: {
      enabled: user.notif_enabled ?? true,
      newMatch: user.notif_new_match ?? true,
      newMessage: user.notif_new_message ?? true,
      likedYou: user.notif_liked_you ?? true,
      superLike: user.notif_super_like ?? true,
      venueActivity: user.notif_venue_activity ?? true
    },
    prompts: prompts
      .sort((lhs, rhs) => lhs.position - rhs.position)
      .map((prompt) => ({
        id: prompt.id,
        question: prompt.question,
        answer: prompt.answer
      })),
    photos: photos
      .sort((lhs, rhs) => lhs.position - rhs.position)
      .map((photo) => ({
        id: photo.id,
        storageKey: photo.storage_key,
        cdnUrl: photo.cdn_url,
        position: photo.position
      }))
  };
}

export function serializeCompactProfile(
  user: UserRow & { photo_url?: string | null; distance?: number | null; has_super_liked_me?: boolean | null }
) {
  return {
    id: user.id,
    name: user.name,
    age: user.age,
    bio: user.bio ?? "",
    profession: user.profession ?? "",
    gender: user.gender ?? "",
    height: user.height ?? 0,
    interests: user.interests ?? [],
    isVerified: user.is_verified,
    isGhostMode: user.is_ghost_mode ?? false,
    photoUrl: user.photo_url ?? null,
    distance: user.distance ?? 0,
    hasSuperLikedMe: user.has_super_liked_me ?? false,
    lookingFor: user.looking_for ?? ""
  };
}
