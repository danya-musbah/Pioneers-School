import {
  characterGroupArtwork,
  characterManifest,
} from "../assets/characters/manifest.js";

const characters = new Map(
  characterManifest.map((character) => [character.id, character]),
);

function pose(characterId, poseName) {
  const file = characters
    .get(characterId)
    ?.files.find((entry) => entry.pose === poseName);
  if (!file)
    throw new Error(`Unknown student artwork: ${characterId}/${poseName}`);
  return file.src;
}

export function normalizeStudentGender(value) {
  const gender = String(value ?? "")
    .trim()
    .replace(/\s+/g, "")
    .normalize("NFKC")
    .toLowerCase();

  if (["male", "m", "ذكر", "ولد", "boy"].includes(gender)) return "male";
  if (["female", "f", "أنثى", "انثى", "بنت", "girl"].includes(gender))
    return "female";

  return "unknown";
}

export const studentPortraitFallbacks = Object.freeze({
  male: pose("boy-with-sign", "hold-sign-look-right"),
  female: pose("side-swept-haired-girl", "hold-sign-look-left"),
  unknown: characterGroupArtwork[0],
});

export const studentArtwork = Object.freeze({
  schoolyardScene: characterGroupArtwork[0],
  neutralPortrait: characterGroupArtwork[0],
  heroCompanion: pose("curly-haired-boy", "wave"),
  home: Object.freeze({
    communityScene: characterGroupArtwork[0],
    communityFigures: Object.freeze([
      pose("first-grade-boy", "stand"),
      pose("short-haired-girl", "stand"),
    ]),
    schedule: Object.freeze({
      active: pose("curly-haired-boy", "look-right"),
      empty: pose("shy-young-girl", "look-down-right"),
    }),
    results: Object.freeze({
      active: pose("blond-ponytailed-girl", "smile-tilt"),
      empty: pose("curly-haired-girl", "surprised-tilt"),
    }),
    fees: Object.freeze({
      active: pose("curly-haired-girl-with-backpack", "hold-book-backpack"),
      empty: pose("boy-with-sign", "hold-sign-look-right"),
    }),
  }),
  pages: Object.freeze({
    profile: pose("boy-with-glasses", "stand"),
    attendance: Object.freeze({
      active: pose("braided-girl", "clasped-hands-tilt"),
      empty: pose("hijab-wearing-girl", "clasped-hands-tilt"),
    }),
    results: pose("blond-boy-with-ball", "hold-ball"),
    fees: Object.freeze({
      active: pose("curly-haired-boy", "think"),
      empty: pose("side-swept-haired-girl", "hold-sign-look-left-alt"),
    }),
    timetable: Object.freeze({
      active: pose("curly-haired-boy", "run-right"),
      empty: pose("shy-young-girl", "look-down-right"),
    }),
    platforms: pose("side-swept-haired-girl", "hold-sign-look-left"),
  }),
});

const usageBySource = new Map([
  [
    studentArtwork.schoolyardScene,
    "مشهد رحلة التعلّم في الصفحة العامة ومجتمع بوابة الطالب",
  ],
  [
    studentArtwork.neutralPortrait,
    "بديل محايد عند غياب الجنس أو عدم التعرف عليه",
  ],
  [studentPortraitFallbacks.male, "الصورة الافتراضية لحساب طالب gender=male"],
  [
    studentPortraitFallbacks.female,
    "الصورة الافتراضية لحساب طالبة gender=female",
  ],
  [studentArtwork.heroCompanion, "رفيق زخرفي في مساحة الترحيب، لا يمثل الطالب"],
  [studentArtwork.home.communityFigures[0], "شخصية ولد في شارة مجتمع الطالب"],
  [studentArtwork.home.communityFigures[1], "شخصية بنت في شارة مجتمع الطالب"],
  [studentArtwork.home.schedule.active, "حالة وجود حصص في ملخص اليوم"],
  [
    studentArtwork.home.schedule.empty,
    "حالة عدم وجود حصص اليوم وعدم نشر الجدول الأسبوعي",
  ],
  [studentArtwork.home.results.active, "حالة وجود نتائج في ملخص الطالب"],
  [studentArtwork.home.results.empty, "حالة عدم وجود نتائج معتمدة"],
  [studentArtwork.home.fees.active, "حالة وجود بنود رسوم في الملخص"],
  [studentArtwork.home.fees.empty, "حالة غياب بنود الرسوم في الملخص"],
  [studentArtwork.pages.profile, "رفيق توضيحي لصفحة الملف الدراسي"],
  [studentArtwork.pages.attendance.active, "صفحة سجل الحضور"],
  [studentArtwork.pages.attendance.empty, "حالة سجل الحضور الفارغ"],
  [studentArtwork.pages.results, "صفحة النتائج المعتمدة"],
  [studentArtwork.pages.fees.active, "صفحة تفاصيل الرسوم المسجلة"],
  [studentArtwork.pages.fees.empty, "حالة عدم وجود رسوم مسجلة"],
  [studentArtwork.pages.timetable.active, "صفحة الجدول المنشور"],
  [studentArtwork.pages.platforms, "حالة الروابط التعليمية غير المهيأة"],
]);

export const studentArtworkInventory = Object.freeze([
  ...characterManifest.flatMap((character) =>
    character.files.map((file) => ({
      path: file.src,
      type: "شخصية مدرسية كاملة",
      usage: usageBySource.get(file.src) ?? "غير معين",
      transparentBackground: file.transparentBackground,
    })),
  ),
  {
    path: characterGroupArtwork[0],
    type: "مشهد مدرسي جماعي بخلفية",
    usage: usageBySource.get(characterGroupArtwork[0]),
    transparentBackground: false,
  },
]);

export const unassignedStudentArtwork = studentArtworkInventory.filter(
  (asset) => !asset.usage || asset.usage === "غير معين",
);
