#version 300 es
void main(){vec2 p=vec2((gl_VertexID<<1)&2,gl_VertexID&2);gl_Position=vec4(p*2.-1.,0,1);}
`;const fs=`#version 300 es
precision highp float;out vec4 o;
uniform vec2 uRes;uniform float uTime;uniform vec3 uCam,uF,uR,uU;uniform float uEnemy;
// add: hurt tint + muzzle flash
uniform float uHurt, uMuzzle;
// + холод страху
uniform float uFear;
// tile texture (walls)
uniform sampler2D uTileTex;
uniform ivec2 uTileSize;     // (cols, rows)
uniform vec2  uTileCenter;   // (cx, cz) як у parseLevel
uniform float uTileScale;    // TILE (розмір тайла)
// multi-cats
const int MAX_CATS = 13;
uniform int uCatCount;
uniform vec4 uCatsPos[MAX_CATS];   // xyz=pos
uniform float uCatsState[MAX_CATS]; // 1.0=black, 2.0=white, 0=hidden
uniform float uCatsEyes[MAX_CATS];  // 0..1
// ---------------- pack/unpack cat id in material value ----------------
// Кодуємо індекс у вигляді 3.00, 3.01, 3.02, ... (крок 0.01)
float packCatId(int i){ return 3.0 + float(i)*0.01; }
int unpackCatId(float m){
  // Перетворюємо назад: (m-3.0)*100 ≈ i, з округленням до найближчого
  int id = int(floor((m - 3.0)*100.0 + 0.5));
  // безпечно обмежуємо
  if(id < 0) id = 0;
  if(id >= MAX_CATS) id = MAX_CATS-1;
  return id;
}

// spheres
const int MAX_SPHERES = 8;
uniform int uSphereCount;
uniform vec4 uSpheresPos[MAX_SPHERES]; // xyz=pos, w=radius (sign: >0 shard, <0 heal)
uniform float uSpheresActive[MAX_SPHERES]; // 1 active, 0 hidden

// sphere id pack/unpack (2.00, 2.01, ...)
float packSphereId(int i){ return 2.0 + float(i)*0.01; }
int unpackSphereId(float m){
  int id = int(floor((m - 2.0)*100.0 + 0.5));
  if(id < 0) id = 0;
  if(id >= MAX_SPHERES) id = MAX_SPHERES-1;
  return id;
}


// + small hashing (deterministic per-tile)
float hash21(vec2 p){ return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453123); }
float hash31(vec3 p){ return fract(sin(dot(p,vec3(17.3,113.1,241.7)))*43758.5453); }
float sdCircle2(vec2 p,float r){ return length(p)-r; }

// Cat paw mask (0..1) in 0..1 UV tile space
float pawMask(vec2 uv){
  // place big pad at uv0, 3 toes above; compact and cheap
  vec2 c = uv - vec2(0.32,0.34);
  float d = sdCircle2(c,0.11);
  d = min(d, sdCircle2(c-vec2(-0.10,0.14),0.050));
  d = min(d, sdCircle2(c-vec2( 0.00,0.16),0.058));
  d = min(d, sdCircle2(c-vec2( 0.10,0.14),0.050));
  return smoothstep(0.03,0.0,d);
}

// Cat-head rune mask (0..1) in 0..1 UV (centered)
float catRune(vec2 uv){
  vec2 p = (uv-0.5);
  // squash a bit for a “feline” look
  p.x/=0.86;
  float d = sdCircle2(p,0.24);              // face
  d = min(d, sdCircle2(p-vec2(-0.18,0.16),0.11)); // ear L
  d = min(d, sdCircle2(p-vec2( 0.18,0.16),0.11)); // ear R
  return smoothstep(0.03,0.0,d);
}


// doors
const int MAX_DOORS = 4;
uniform int uDoorCount;
uniform vec4 uDoorsPos[MAX_DOORS];  // xyz=center
uniform vec4 uDoorsHalf[MAX_DOORS]; // xyz=half-size, w=activeFlag(>0 = активні/“сексуальні”)

// door id pack/unpack (5.00, 5.01, 5.02, ...)
float packDoorId(int i){ return 5.0 + float(i)*0.01; }
int unpackDoorId(float m){
  int id = int(floor((m - 5.0)*100.0 + 0.5));
  if(id < 0) id = 0;
  if(id >= MAX_DOORS) id = MAX_DOORS-1;
  return id;
}
// turrets (sentinel idols)
const int MAX_TURRETS = 6;
uniform int uTurretCount;
uniform vec4 uTurretsPos[MAX_TURRETS]; // xyz=base position
// NEW: boss uniforms
uniform int uBossActive;
uniform vec4 uBoss;       // xyz=pos, w=scale
uniform float uBossEyes;  // 0..1
uniform float uBossPhase; // 1..5
float packTurretId(int i){ return 6.0 + float(i)*0.01; }
int unpackTurretId(float m){
  int id = int(floor((m - 6.0)*100.0 + 0.5));
  if(id < 0) id = 0;
  if(id >= MAX_TURRETS) id = MAX_TURRETS-1;
  return id;
}
float sdSphere(vec3 p,float r){return length(p)-r;}
float sdRect(vec2 p,vec2 b){vec2 d=abs(p)-b;return min(max(d.x,d.y),0.)+length(max(d,0.));}

// === helpers (ГЛОБАЛЬНО, не всередині map!) ===
float sdCapsule(vec3 q, vec3 a, vec3 b, float r){
  vec3 pa=q-a, ba=b-a;
  float h=clamp(dot(pa,ba)/dot(ba,ba),0.0,1.0);
  return length(pa-ba*h)-r;
}
float sdEllipsoid(vec3 q, vec3 s){
  return (length(q/s)-1.0)*min(min(s.x,s.y),s.z);
}
float sdBox(vec3 p, vec3 b){
  vec3 d=abs(p)-b;
  return min(max(d.x,max(d.y,d.z)),0.) + length(max(d,0.));
}

// smooth union (м’яке складання форм) — щоб голова не виглядала з «кульок»
float smin(float a, float b, float k){
  // k ~ 0.04..0.12 для наших масштабів; більше = плавніше
  float h = clamp(0.5 + 0.5*(b - a)/k, 0.0, 1.0);
  return mix(b, a, h) - k*h*(1.0 - h);
}
float opInter(float a, float b){ return max(a,b); } // (припасовано для вух, якщо треба)


// дві площини y=±h (поверхні, НЕ заповнений шар)
float sdTwoPlanesY(vec3 p, float h){
  return min(abs(p.y - h), abs(p.y + h));
}
float sdCatModelAt(vec3 q, vec3 catPos){
  q -= catPos;
  float d = 1e9;

  // Torso (котячий: гнучка спина, тонший попереду)
  d = min(d, sdEllipsoid(q - vec3(-0.06, 0.03, 0.00), vec3(0.58, 0.24, 0.28))); // тулуб
  // Chest/shoulders (виступаюча лопатка кота)
  d = min(d, sdEllipsoid(q - vec3( 0.18, 0.01, 0.00), vec3(0.22, 0.14, 0.22)));
  // Gentle back arch + slight belly
  d = min(d, sdEllipsoid(q - vec3(-0.10, 0.07, 0.00), vec3(0.52, 0.20, 0.26))); // арка спини
  d = min(d, sdEllipsoid(q - vec3( 0.03,-0.06, 0.00), vec3(0.28, 0.11, 0.20))); // легкий «пузик»


  // Neck (коротша, стрункіша — котяча посадка голови)
  d = min(d, sdCapsule(q, vec3(0.36,0.10,0.17), vec3(0.48,0.14,0.17), 0.070));

  // === HEAD (smooth, feline) ==========================================
  // Збираємо голову однією SDF через smin, щоб не було «кульок».
  {
    // базова «черепна» форма: плаский лоб, округлі щоки
    float hd  = sdEllipsoid(q - vec3(0.585,0.160,0.170), vec3(0.155,0.125,0.135));
    // скулові дуги (ширина морди)
    float hZL = sdEllipsoid(q - vec3(0.575,0.150,0.255), vec3(0.105,0.070,0.070));
    float hZR = sdEllipsoid(q - vec3(0.575,0.150,0.085), vec3(0.105,0.070,0.070));
    // whisker pads — ближче до низу, округлі
    float hWL = sdEllipsoid(q - vec3(0.635,0.108,0.230), vec3(0.088,0.058,0.078));
    float hWR = sdEllipsoid(q - vec3(0.635,0.108,0.110), vec3(0.088,0.058,0.078));
    // короткий snout (НЕ «собачий»): коротко і вузько
    float hSN = sdEllipsoid(q - vec3(0.690,0.095,0.170), vec3(0.060,0.045,0.060));
    // легке сплощення лоба коробкою — котячий профіль
    float hFL = sdBox(q - vec3(0.570,0.185,0.170), vec3(0.120,0.030,0.120));

    // плавні з’єднання
    float k = 0.08; // радіус «плавності»
    hd = smin(hd, hZL, k);
    hd = smin(hd, hZR, k);
    hd = smin(hd, hWL, k);
    hd = smin(hd, hWR, k);
    hd = smin(hd, hSN, k*0.85);
    hd = smin(hd, hFL, k*0.70);

    d = min(d, hd);
  }

  // Ears — коротші, тонші, без «труб»
  {
    vec3 eBL = vec3(0.620,0.292,0.100), eTL = vec3(0.640,0.332,0.095);
    vec3 eBR = vec3(0.620,0.292,0.240), eTR = vec3(0.640,0.332,0.245);
    float earL = smin(sdBox(q - eBL, vec3(0.046,0.085,0.026)),
                      sdBox(q - eTL, vec3(0.030,0.050,0.018)), 0.06);
    float earR = smin(sdBox(q - eBR, vec3(0.046,0.085,0.026)),
                      sdBox(q - eTR, vec3(0.030,0.050,0.018)), 0.06);
    d = min(d, earL);
    d = min(d, earR);
  }

  // Legs: котячі пропорції — сухі плечі, опуклі стегна
  // передні (тонша верхня половина)
  d = min(d, sdCapsule(q, vec3( 0.05,-0.12, 0.20), vec3( 0.05,-0.48, 0.20), 0.038)); // front L
  d = min(d, sdCapsule(q, vec3( 0.05,-0.12,-0.20), vec3( 0.05,-0.48,-0.20), 0.038)); // front R
  // задні (виразніше «стегно»)
  d = min(d, sdEllipsoid(q - vec3(-0.31,-0.06, 0.25), vec3(0.13,0.095,0.105))); // thigh L
  d = min(d, sdEllipsoid(q - vec3(-0.31,-0.06,-0.25), vec3(0.13,0.095,0.105))); // thigh R
  d = min(d, sdCapsule(q, vec3(-0.34,-0.16, 0.25), vec3(-0.34,-0.46, 0.25), 0.053)); // shank L
  d = min(d, sdCapsule(q, vec3(-0.34,-0.16,-0.25), vec3(-0.34,-0.46,-0.25), 0.053)); // shank R


  // Tail (tapered S-curve)
  // вищий вихід із крупу і сильніше звуження — котячий жест
  d = min(d, sdCapsule(q, vec3(-0.62, 0.00, 0.02), vec3(-0.92, 0.19, 0.02), 0.036));
  d = min(d, sdCapsule(q, vec3(-0.92, 0.19, 0.02), vec3(-1.02, 0.36,-0.06), 0.030));
  d = min(d, sdCapsule(q, vec3(-1.02, 0.36,-0.06), vec3(-1.07, 0.47, 0.10), 0.024));

  return d;
}
// NEW: scaled cat SDF
float sdCatScaled(vec3 p, vec3 c, float s){
  vec3 q = c + (p - c)/s;
  return sdCatModelAt(q, c) * s;
}
// return (dist,matId)
vec2 map(vec3 p){
  float d=1e9, m=0.;
  // підлога/стеля (мат 4) — відстань до найближчої площини
  float dFloor = sdTwoPlanesY(p, 0.6);
  if(dFloor<d){ d=dFloor; m=4.; }
  // стіни/колони з TILE TEXTURE — 3×3 локальне оточення (мат 1)
  // обчислюємо індекс поточного тайла з p.xz (інверс до parseLevel)
  int ix = int(floor(p.x / uTileScale + uTileCenter.x + 0.5));
  int iz = int(floor(-p.z / uTileScale + uTileCenter.y + 0.5));
  for(int dz=-1; dz<=1; dz++){
    for(int dx=-1; dx<=1; dx++){
      int tx = ix + dx;
      int tz = iz + dz;
      if(tx<0 || tz<0 || tx>=uTileSize.x || tz>=uTileSize.y) continue;
      // семпл з текстури (0..255)
      float code = texture(uTileTex, (vec2(tx, tz)+0.5)/vec2(uTileSize)).r * 255.0;
      if(code < 0.5) continue; // порожньо
      // центр тайла в світі (як у parseLevel: (col-cx)*TILE, z=-(row-cz)*TILE)
      vec3 c = vec3( (float(tx)-uTileCenter.x)*uTileScale, 0.0, -(float(tz)-uTileCenter.y)*uTileScale );
      vec3 b = vec3(uTileScale*0.48, 0.6, uTileScale*0.48);
      // швидка груба відсічка
      vec3 d3 = abs(p - c) - b;
      float rough = max(max(d3.x,d3.y), d3.z);
      if(rough > d) continue;
      float db = sdBox(p - c, b);
      if(db < d){ d=db; m=1.; }
    }
  }  
  // сфери з карти (мат 2.xx)
  for(int i=0;i<MAX_SPHERES;i++){
    if(i>=uSphereCount) break;
    if(uSpheresActive[i] < 0.5) continue;
    vec3 sp = uSpheresPos[i].xyz;
    float rr = abs(uSpheresPos[i].w);
    float ds = sdSphere(p - sp, rr);
    if(ds < d){ d=ds; m=packSphereId(i); }
  }
  // кіт (мат 3.xx, де xx — індекс*0.01) — масив
  for(int i=0;i<MAX_CATS;i++){
    if(i>=uCatCount) break;
    if(uCatsState[i] < 0.5) continue; // hidden
    vec3 cp = uCatsPos[i].xyz;
    float dc = sdCatModelAt(p, cp);
    if(dc < d){ d=dc; m=packCatId(i); }
  }
  // двері (мат 5.xx) — світний тонкий бокс
  for(int i=0;i<MAX_DOORS;i++){
    if(i>=uDoorCount) break;
    vec3 dp = uDoorsPos[i].xyz;
    vec3 dh = uDoorsHalf[i].xyz;
    float dd = sdBox(p - dp, dh);
    if(dd < d){ d=dd; m=packDoorId(i); }
  }
    // турелі/ідоли (мат 6.xx) — стрижень + «око»-куля
    for(int i=0;i<MAX_TURRETS;i++){
      if(i>=uTurretCount) break;
      vec3 tp = uTurretsPos[i].xyz;
      // pole: slim capsule
      float dp = sdCapsule(p, tp + vec3(0.0,-0.45,0.0), tp + vec3(0.0,0.30,0.0), 0.035);
      if(dp < d){ d=dp; m=packTurretId(i); }
      // eye orb: small sphere floating above
      float de = sdSphere(p - (tp + vec3(0.0,0.38,0.0)), 0.11);
      if(de < d){ d=de; m=packTurretId(i); }
  }
  // NEW: boss (мат 7.00)
  if(uBossActive>0){
    float db = sdCatScaled(p, uBoss.xyz, uBoss.w);
    if(db<d){ d=db; m=7.0; }
  }
  return vec2(d,m);
}
vec2 march(vec3 ro,vec3 rd){
  float t = 0.0;
  float m = 0.0;
  // Менше кроків (швидше), але з розумним раннім виходом
  for (int i=0; i<128; i++) {
    vec2 h = map(ro + rd*t);
    // dynamic epsilon: далі = грубіше, ближче = точніше
    float eps = mix(0.001, 0.015, clamp((t - 5.0)/20.0, 0.0, 1.0));
    if (h.x < eps) { m = h.y; break; }
    t += h.x;
    // межа сцени
    if (t > 40.0) { m = 0.0; break; }
    // трохи густіший туман для раннього виходу
    if (exp(-0.09 * t) < 0.02) { m = 0.0; break; }
  }
  return vec2(t, m);
}
vec3 nrm(vec3 p){
  float e=0.001;
  vec2 k=vec2(1,-1);
  return normalize(
    k.xyy*map(p+k.xyy*e).x+
    k.yyx*map(p+k.yyx*e).x+
    k.yxy*map(p+k.yxy*e).x+
    k.xxx*map(p+k.xxx*e).x);
}
void main(){
  vec2 uv=(gl_FragCoord.xy-0.5*uRes)/uRes.y;
  vec3 rd=normalize(uv.x*uR+uv.y*uU+uF);
  vec2 h=march(uCam,rd); float t=h.x, mat=h.y;
  vec3 bg=vec3(0.02,0.02,0.04);
  // Якщо вийшли по туману/межі — не рахуємо нормалі (економія)
  if (t>40. || mat<0.5) { o=vec4(bg,1.0); return; }
  vec3 p=uCam+rd*t;
  // для підлоги/стелі нормаль відома — економимо 4 map-виклики
  vec3 n = (mat>3.5 && mat<4.5) ? vec3(0.0, (p.y>0.0)?1.0:-1.0, 0.0) : nrm(p);
  
  // Helpers: tile indices + per-tile uv (0..1)
  float fx = (p.x/uTileScale + uTileCenter.x);
  float fz = (-p.z/uTileScale + uTileCenter.y);
  int   ix = int(floor(fx+0.5));
  int   iz = int(floor(fz+0.5));
  vec2  tuv = fract(vec2(fx,fz)); // floor/ceiling uv per tile
  
  // materials (1=wall, 2=sphere, 3.xx=cat(index), 4=floor/ceiling, 5=door)
  vec3 col;
  // обчислимо id кота / дверей, якщо влучили
  int ciHit = -1, diHit = -1, siHit = -1;
  int tiHit = -1;
  if(mat >= 3.0 && mat < 4.0) ciHit = unpackCatId(mat);
  if(mat >= 5.0 && mat < 6.0) diHit = unpackDoorId(mat);
  if(mat >= 2.0 && mat < 3.0) siHit = unpackSphereId(mat);
  if(mat >= 6.0 && mat < 7.0) tiHit = unpackTurretId(mat);


  if(mat < 1.5){
    // WALLS — спокійний холодний камінь; руни — ледь видні, без пульсу
    col = mix(vec3(0.09,0.10,0.11), vec3(0.12,0.13,0.14),
              0.5 + 0.5*sin((p.x*1.7+p.z*1.3)*0.4)); // низька амплітуда
    // plane uv
    float u = (abs(n.x) > abs(n.z)) ? fract(-p.z/uTileScale + uTileCenter.y)
                                    : fract( p.x/uTileScale + uTileCenter.x);
    float v = clamp((p.y+0.6)/1.2,0.0,1.0);
    vec2 wuv=vec2(u,v);
    // рідкі руни — спокійний ціан, без часу
    float r = hash21(vec2(ix,iz)*1.23);
    if(r < 0.16){
      float m = catRune(wuv);
      col = mix(col, col + vec3(0.00,0.08,0.12), m*0.28);
    }
  } else if(mat < 3.0){
    // сфери: зелений (шард) або ціан (хіл) або червоно-пурпурний (орб)
    bool isHeal = false;
    bool isProj = false;
    if(siHit>=0 && siHit<uSphereCount){
      isHeal = (uSpheresPos[siHit].w < 0.0);
      isProj = (uSpheresActive[siHit] > 1.5);
    }
    if(isProj){
      float pulse = 0.5 + 0.5*sin(uTime*8.0);
      col = vec3(0.10,0.02,0.03) + pulse*vec3(1.8,0.3,0.6);
    } else if(isHeal){
      col = vec3(0.05,0.10,0.12) + 0.8*vec3(0.2,0.9,1.6);
    } else {
      col = vec3(0.05,0.12,0.04) + 0.7*vec3(0.2,0.9,0.2);
    }
  } else if(mat < 4.0){
    // кіт: беремо стан саме того кота, в якого влучили
    float state = (ciHit>=0 && ciHit<uCatCount) ? uCatsState[ciHit] : 1.0; // 1=black, 2=white
    if(state < 1.5){
      // BLACK — темний + червоний Fresnel rim
      col = vec3(0.02,0.02,0.03);
      float fr = pow(1.0 - max(dot(n, -rd), 0.0), 3.0);
      col += fr * vec3(0.35, 0.05, 0.05);
    } else {
      // WHITE — примарне мерехтіння цианом
      col = vec3(0.85);
      float flick = 0.5 + 0.5*sin(uTime*20.0 + p.x*10.0 + p.z*7.0);
      col += vec3(0.15,0.45,0.55) * flick;
    }
  } else if(mat < 4.5){
    // FLOOR / CEILING — stone base + per-tile variety
    bool isCeil = (n.y>0.0);
    col = mix(vec3(0.10), vec3(0.18,0.19,0.20), 0.5 + 0.5*sin(p.x*2.0));
    float rv = hash21(vec2(ix,iz));
    if(!isCeil){
      // Floor variants
      if(rv < 0.33){
        // Paw prints (subtle, darkened + red tint)
        float paw = pawMask(tuv);
        col = mix(col, col*0.60 + vec3(0.03,0.00,0.00), paw*0.75);
      } else if(rv < 0.66){
        // Cracks: warped sine linework
        float w = abs(sin((tuv.x*18.0 + sin(tuv.y*6.0 + rv*6.0))*1.0));
        float crack = smoothstep(0.06,0.03, w);
        col -= crack*0.07;
      } // else plain stone
    } else {
      // Ceiling: faint cyan mold/scratches
      float str = abs(sin((tuv.x+tuv.y + rv)*14.0))*0.5 + abs(sin((tuv.x*2.0 - tuv.y)*9.0))*0.5;
      float mold = smoothstep(1.0,0.85,str);
      col = mix(col, col + vec3(0.00,0.12,0.16), mold*0.20);
    }
  } else if(mat < 5.5){
    // ДВЕРІ: відрізняються від стін — панельне мерехтіння (в обох станах), активні — яскраві
    float door_active = (diHit>=0 && diHit<uDoorCount) ? step(0.5, uDoorsHalf[diHit].w) : 0.0;
    vec3 dp = uDoorsPos[diHit].xyz;
    vec3 dh = uDoorsHalf[diHit].xyz;
    vec3 lp = p - dp;
    bool faceX = (dh.x < dh.z);
    vec2 uvd = faceX
      ? vec2((lp.z/dh.z)*0.5+0.5, (lp.y/dh.y)*0.5+0.5)
      : vec2((lp.x/dh.x)*0.5+0.5, (lp.y/dh.y)*0.5+0.5);
    uvd = clamp(uvd, 0.0, 1.0);

    // базовий камінь дверей
    vec3 base = vec3(0.08,0.08,0.10);

    // повне «панельне» мерехтіння
    float panel = 0.55 + 0.45*sin(uTime*1.8 + float(diHit)*1.3);
    vec3 colOff = vec3(0.35, 0.10, 0.55);   // неактивні — холодно-фіолетові
    vec3 colOn  = vec3(1.60, 0.35, 0.90);   // активні — яскраво-магентні
    vec3 eCol   = mix(colOff, colOn, door_active);

    // шов та край
    float seam = smoothstep(0.06, 0.00, abs(uvd.x-0.5));
    float edge = smoothstep(0.10, 0.00, min(min(uvd.x,1.0-uvd.x), min(uvd.y,1.0-uvd.y)));

    // символіка
    float rune = catRune(uvd);
    vec2 pawUV = fract(uvd*vec2(2.0,1.5) + vec2(0.0,-0.15));
    float paw = pawMask(pawUV) * smoothstep(0.4, 0.9, uvd.y);

    // трохи підсилюємо емісію з відстанню — краще пробиває туман
    float eBoost = mix(1.0, 1.8, smoothstep(8.0, 24.0, t));

    vec3 emiss = vec3(0.0);
    emiss += panel * (0.22 + 0.28*door_active) * eCol;
    emiss += seam  * (0.14 + 0.24*door_active) * eCol;
    emiss += edge  * (0.08 + 0.22*door_active) * eCol;
    emiss += (0.28*rune + 0.22*paw) * (0.4 + 0.6*(0.5+0.5*sin(uTime*6.0+float(diHit)))) * eCol;
    emiss *= eBoost;

    col = base + emiss;
  } else if(mat < 7.0){
    // турель: базальтовий стрижень + «око» з емісією
    col = vec3(0.08,0.08,0.10);
    if(tiHit>=0 && tiHit<uTurretCount){
      vec3 tp = uTurretsPos[tiHit].xyz;
      float dEye = length(p - (tp + vec3(0.0,0.45,0.0)));
      float pulse = 0.6 + 0.4*sin(uTime*3.0 + float(tiHit)*1.7);
      // eye glow if near the eye sphere
      float glow = smoothstep(0.20, 0.03, dEye);
      col += glow * (vec3(0.10,0.02,0.05) + pulse*vec3(1.00,0.30,0.90));
      // faint runic tint along pole even when not on eye
      float poleBand = 0.15 + 0.85*abs(sin((p.y+tp.y+1.5)*6.0));
      col = mix(col, col + vec3(0.06,0.01,0.08)*pulse, 0.25*poleBand);
    }
  } else if(mat < 8.0){
    // NEW: boss look — black with purple rim; eyes glow when open
    col = vec3(0.02,0.02,0.03);
    float fr = pow(1.0 - max(dot(n, -rd), 0.0), 3.0);
    col += fr * vec3(0.40, 0.10, 0.45);
    if(uBossEyes>0.0){
      vec3 pr = p - uBoss.xyz;
      float eL = length(pr - vec3(0.662,0.172,0.238)*uBoss.w);
      float eR = length(pr - vec3(0.662,0.172,0.102)*uBoss.w);
      float glow = uBossEyes * smoothstep(0.20*uBoss.w, 0.04*uBoss.w, min(eL,eR));
      col += glow * vec3(2.2, 0.5, 2.6);
    }
  } else {
    // бекграунд fallback (не має траплятись, але на всяк випадок)
    col = vec3(0.1);
  }
  vec3 l=normalize(vec3(0.4,0.6,0.7));
  float diff=max(0.05,dot(n,l));
  col*=diff + (mat>2.5 ? 0.3 : 0.3);
  // Eyes glow (emission) — тільки для того кота, якого ми рендеримо
  if(ciHit >= 0 && ciHit < uCatCount){
    float eyes = uCatsEyes[ciHit];
    if(eyes > 0.0){
      vec3 pr = p - uCatsPos[ciHit].xyz;
      // feline eye anchors — трохи вище і ширше під новий череп
      float eyeL = length(pr - vec3(0.662,0.172,0.238));
      float eyeR = length(pr - vec3(0.662,0.172,0.102));
      float dEye = min(eyeL, eyeR);
      // чутливіший «зіниця»-глоу, щоб не «перепікало» морду
      float glow = eyes * smoothstep(0.10, 0.028, dEye);
      float stateE = (ciHit>=0 && ciHit<uCatCount) ? uCatsState[ciHit] : 1.0;
      vec3 glowCol = (stateE < 1.5) ? vec3(3.0, 0.6, 0.2) : vec3(0.6, 1.6, 2.3);
      col += glow * glowCol;
    }
  }
  float fog=exp(-0.09*t);
  vec3 colFog = mix(bg,col,fog);
  // blood tint (hurt)
  colFog = mix(colFog, vec3(0.45,0.0,0.0), clamp(uHurt,0.0,1.0));
  // fear cold tint (blue-cyan)
  colFog = mix(colFog, vec3(0.0,0.22,0.33), clamp(uFear,0.0,1.0));
  // muzzle flash bloom at screen center
  float flash = uMuzzle * smoothstep(0.6, 0.0, length(uv));
  colFog += flash * 0.6;
  colFog *= 1.3; // global brighten factor
  o=vec4(colFog,1.0);  
}