// Audited, locally bundled character art. Names are neutral asset aliases, not student records.
// Feet anchors are normalized to each image's box (0–1); check each pose's visible shoe line before placement.
export const characterManifest = [
  {
    id: "curly-haired-boy",
    name: "آدم",
    personality: "ودود وفضولي",
    anchor: { x: 0.5, y: 0.985 },
    files: [
      {
        src: "assets/images/Schoolboy-Curly-Hair-Smiling-Waving-Alternate-Uniform.png",
        pose: "wave",
        transparentBackground: true,
      },
      {
        src: "assets/images/Schoolboy-Curly-Hair-Smiling-Waving-Looking-Right.png",
        pose: "look-right",
        transparentBackground: true,
      },
      {
        src: "assets/images/Schoolboy-Curly-Hair-Thinking-Looking-Upper-Right.png",
        pose: "think",
        transparentBackground: true,
      },
      {
        src: "assets/images/Schoolboy-First-Grade-Running-Right-Backpack.png",
        pose: "run-right",
        transparentBackground: false,
      },
    ],
  },
  {
    id: "blond-boy-with-ball",
    name: "سليم",
    personality: "نشيط ورياضي",
    anchor: { x: 0.5, y: 0.985 },
    files: [
      {
        src: "assets/images/Schoolboy-First-Grade-Blonde-Hair-Smiling-Holding-Ball.png",
        pose: "hold-ball",
        transparentBackground: false,
      },
    ],
  },
  {
    id: "first-grade-boy",
    name: "يونس",
    personality: "هادئ وملاحظ",
    anchor: { x: 0.5, y: 0.985 },
    files: [
      {
        src: "assets/images/Schoolboy-First-Grade-Standing-Front-Facing-Arms-Sides.png",
        pose: "stand",
        transparentBackground: false,
      },
    ],
  },
  {
    id: "boy-with-glasses",
    name: "باسل",
    personality: "محب للقراءة",
    anchor: { x: 0.5, y: 0.985 },
    files: [
      {
        src: "assets/images/Schoolboy-Fourth-Grade-Glasses-Standing-Front-Facing.png",
        pose: "stand",
        transparentBackground: false,
      },
    ],
  },
  {
    id: "boy-with-sign",
    name: "مالك",
    personality: "مبادر ومرح",
    anchor: { x: 0.5, y: 0.985 },
    files: [
      {
        src: "assets/images/Schoolboy-Standing-Holding-Sign-Looking-Right.png",
        pose: "hold-sign-look-right",
        transparentBackground: true,
      },
    ],
  },
  {
    id: "short-haired-girl",
    name: "ليان",
    personality: "هادئة وواثقة",
    anchor: { x: 0.5, y: 0.985 },
    files: [
      {
        src: "assets/images/Schoolgirl-First-Grade-Short-Hair-Standing-Front-Facing.png",
        pose: "stand",
        transparentBackground: false,
      },
    ],
  },
  {
    id: "curly-haired-girl",
    name: "مريم",
    personality: "فضولية ومندهشة",
    anchor: { x: 0.5, y: 0.985 },
    files: [
      {
        src: "assets/images/Schoolgirl-Fourth-Grade-Curly-Hair-Surprised-Expression-Head-Tilt.png",
        pose: "surprised-tilt",
        transparentBackground: false,
      },
    ],
  },
  {
    id: "hijab-wearing-girl",
    name: "سلمى",
    personality: "لطيفة ومطمئنة",
    anchor: { x: 0.5, y: 0.985 },
    files: [
      {
        src: "assets/images/Schoolgirl-Ninth-Grade-White-Hijab-Smiling-Clasped-Hands-Head-Tilt.png",
        pose: "clasped-hands-tilt",
        transparentBackground: false,
      },
    ],
  },
  {
    id: "curly-haired-girl-with-backpack",
    name: "جود",
    personality: "مرحة واجتماعية",
    anchor: { x: 0.5, y: 0.985 },
    files: [
      {
        src: "assets/images/Schoolgirl-Second-Grade-Black-Skin-Smiling-Holding-Sign-Backpack.png",
        pose: "hold-book-backpack",
        transparentBackground: false,
      },
    ],
  },
  {
    id: "braided-girl",
    name: "تالا",
    personality: "صبورة ومتعاونة",
    anchor: { x: 0.5, y: 0.985 },
    files: [
      {
        src: "assets/images/Schoolgirl-Seventh-Grade-Black-Side-Braid-Smiling-Clasped-Hands-Head-Tilt.png",
        pose: "clasped-hands-tilt",
        transparentBackground: false,
      },
    ],
  },
  {
    id: "side-swept-haired-girl",
    name: "نور",
    personality: "مبدعة وودودة",
    anchor: { x: 0.5, y: 0.985 },
    files: [
      {
        src: "assets/images/Schoolgirl-Side-Swept-Hair-Holding-Sign-Looking-Left.png",
        pose: "hold-sign-look-left",
        transparentBackground: true,
      },
      {
        src: "assets/images/Schoolgirl-Standing-Holding-Sign-Looking-Left.png",
        pose: "hold-sign-look-left-alt",
        transparentBackground: true,
      },
    ],
  },
  {
    id: "blond-ponytailed-girl",
    name: "رنا",
    personality: "متفائلة وملاحظة",
    anchor: { x: 0.5, y: 0.985 },
    files: [
      {
        src: "assets/images/Schoolgirl-Sixth-Grade-Blonde-Ponytail-Smiling-Head-Tilt.png",
        pose: "smile-tilt",
        transparentBackground: false,
      },
    ],
  },
  {
    id: "shy-young-girl",
    name: "هدى",
    personality: "خجولة وفضولية",
    anchor: { x: 0.5, y: 0.985 },
    files: [
      {
        src: "assets/images/Young-Schoolgirl-Short-Shy-Smile-Looking-Lower-Right.png",
        pose: "look-down-right",
        transparentBackground: true,
      },
    ],
  },
];

// The two schoolyard-friends images are group compositions, not separable character layers.
export const characterGroupArtwork = [
  "assets/images/Cheerful-Schoolyard-Friends-With-Background.png",
];
