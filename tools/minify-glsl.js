// tools/minify-glsl.js
const fs = require("fs");

function minifyGLSL(src) {
  // 1) прибрати блок-коментарі (без захоплення препроцесора)
  src = src.replace(/\/\*[\s\S]*?\*\//g, "");
  // 2) прибрати однорядкові коментарі (але не в препроцесорних рядках)
  src = src.replace(/(^|\n)[ \t]*\/\/.*(?=\n|$)/g, "$1");
  // 3) зберегти \n після препроцесора (#define/#ifdef/… мають бути з початку рядка)
  // сплющити інше: зайві пробіли/переноси → один пробіл
  src = src
    .split("\n")
    .map(l => {
      if (/^\s*#/.test(l)) return l.trim(); // препроцесор лишаємо
      return l
        .replace(/\s+/g, " ")   // стиснути пробіли
        .replace(/\s*([=+\-*/%<>&|^!?,:;(){}\[\]])\s*/g, "$1") // пробіли довкола операторів
        .trim();
    })
    .filter(l => l.length)
    .join("\n");

  // 4) дрібні мікро-скорочення
  src = src
    .replace(/\bfloat\s+/g, "float ")
    .replace(/\bint\s+/g, "int ")
    .replace(/\bvec2\s*\(\s*([^)]+?)\s*\)/g, (m, a) => `vec2(${a})`)
    .replace(/\bvec3\s*\(\s*([^)]+?)\s*\)/g, (m, a) => `vec3(${a})`)
    .replace(/\bvec4\s*\(\s*([^)]+?)\s*\)/g, (m, a) => `vec4(${a})`)
    // pow(x,2.0) -> (x*x)
    .replace(/\bpow\(\s*([^)]+?)\s*,\s*2\.0\s*\)/g, "($1*$1)")
    // step/smoothstep часто коротше за умовний оператор — не чіпаємо тут.
    ;

  return src;
}

if (require.main === module) {
  const inFile = process.argv[2];
  const outFile = process.argv[3] || inFile.replace(/(\.\w+)?$/, ".min$1");
  const src = fs.readFileSync(inFile, "utf8");
  fs.writeFileSync(outFile, minifyGLSL(src));
  console.log(`GLSL minified: ${inFile} → ${outFile}`);
}

module.exports = { minifyGLSL };
// Використання: node tools/minify-glsl.js shader.frag.glsl shader.frag.min.glsl
