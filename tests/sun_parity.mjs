import fs from "fs";
import path from "path";
import { fileURLToPath } from "url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const src = fs.readFileSync(path.join(root, "app.js"), "utf8");
const match = src.match(/\/\* SUN_BLOCK_START \*\/([\s\S]*?)\/\* SUN_BLOCK_END \*\//);
if (!match) {
  console.error("app.js is missing the sun block markers");
  process.exit(1);
}
const sunTimes = new Function(`${match[1]}\nreturn sunTimes;`)();

function stamp(date) {
  if (!(date instanceof Date) || !Number.isFinite(date.getTime())) return null;
  return date.toISOString();
}

const cases = [
  { name: "nyc-summer", iso: "2026-06-21T16:00:00.000Z", lat: 40.7128, lon: -74.006 },
  { name: "london-winter", iso: "2026-12-21T12:00:00.000Z", lat: 51.5074, lon: -0.1278 },
  { name: "equator-equinox", iso: "2026-03-20T12:00:00.000Z", lat: 0, lon: 0 },
  { name: "high-arctic", iso: "2026-01-15T00:00:00.000Z", lat: 89, lon: 0 }
];

const golden = cases.map((item) => {
  const sun = sunTimes(new Date(item.iso), item.lat, item.lon);
  return {
    ...item,
    sunrise: stamp(sun.sunrise),
    sunset: stamp(sun.sunset),
    solarNoon: stamp(sun.solarNoon),
    goldenMorningEnd: stamp(sun.goldenMorningEnd),
    goldenEveningStart: stamp(sun.goldenEveningStart),
    blueMorningStart: stamp(sun.blueMorning[0]),
    blueMorningEnd: stamp(sun.blueMorning[1]),
    blueEveningStart: stamp(sun.blueEvening[0]),
    blueEveningEnd: stamp(sun.blueEvening[1])
  };
});

const outPath = path.join(root, "ios/Logic/Tests/StopAndShootLogicTests/Fixtures/sun_golden.json");
if (process.argv.includes("--write")) {
  fs.mkdirSync(path.dirname(outPath), { recursive: true });
  fs.writeFileSync(outPath, JSON.stringify(golden, null, 2) + "\n");
  console.log("wrote", outPath);
} else {
  const saved = JSON.parse(fs.readFileSync(outPath, "utf8"));
  if (JSON.stringify(saved) !== JSON.stringify(golden)) {
    console.error("sun golden drifted from app.js. Run: node tests/sun_parity.mjs --write");
    process.exit(1);
  }
  console.log(`sun parity ok (${golden.length} cases)`);
}
