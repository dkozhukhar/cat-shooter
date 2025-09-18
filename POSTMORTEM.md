# Making of: Short and polished notes on how my 2025 js13k game Cat Shooter Ritual Catacombs was born

![Preview 800x500](https://github.com/dkozhukhar/cat-shooter/blob/main/preview_img/preview_800x500_200kb.png)

## Concept and Idea

This year I experimented heavily with agentic workflows, and recalling my earlier participation in the contest, I ran many tests on how AI could handle creating games. When the jam began, I couldn’t resist trying again. Later in those experiments I stumbled into the idea of a 3D shooter with cats — black cats to scare players, white cats to confuse them (friendly at first, then turning hostile, or transforming into ghosts). The very first prototype was simply an infinite corridor with a ball, but once cats entered the picture the theme clicked. The naming was a patchwork: *Catacombs* came from that corridor feeling, *Ritual* appeared when I needed a phrase for player death (“ritual failed”), and *Cat Shooter* was just the quick label I gave the GitHub repository for my first draft. Together they stuck as Cat Shooter Ritual Catacombs.

*Gameplay Video*

[![Gameplay video](https://img.youtube.com/vi/VKJWRrND6bM/0.jpg)](https://www.youtube.com/watch?v=VKJWRrND6bM)

## Development Process

* **Early experiments.** I tried several small games in the first two weeks, including an RTS prototype. The RTS died at \~600 lines due to canvas interface limits, but it pushed me to explore better pipelines.
* **Switch to 3D shooter.** My first shooter prototypes looked like Wolf3D. Later WebGL/raymarching experiments felt cooler and promising, so I stuck with them.
* **One feature at a time.** This became my mantra. Each new addition required optimization cycles. Adding more cats or larger levels forced me to learn and streamline.
* **Pipeline.** I worked in GitHub Codespaces, with commits after each stable step. I learned to always keep `main` working, and never rely on unsaved drafts. Three.js was too heavy, so I stuck with native GL and shaders.
* **AI as helper and buddy.** I used ChatGPT (Plus/API) to plan, add features step by step, and debug. It worked best when I asked for one thing at a time, and it kept me company when motivation dipped.

## What Went Right

* Clear theme: scary/friendly cats created tension and atmosphere.
* Playable prototype early enough to guide development.
* Final boss (*ChornoCot*) was added in the last days, yet fit smoothly.
* Learned a lot: shaders, GitHub workflow, mental strategy for jam dev.
* Finished and submitted — not just a demo, but a working short game.

## What Went Wrong

* **RTS attempt.** Too ambitious for a jam. Lesson: RTS are hell — though I will definitely try again in the future.
* **Scope creep.** Ideas like labyrinths, open spaces, flying shooter, or z-plane were cut due to time and energy.
* **Sound.** Sound was very minimal — I didn’t know how to handle it properly and only left basic elements, though there is a huge space for what could be done.
* **Playtime.** The whole game can be finished in \~5 minutes. After spending 20–40 hours, this ratio felt funny (or painful).
* **Fatigue.** By the final days I was exhausted, the pace slowed a lot, and many planned things were simply left out to wrap it up.

## Interesting Technical Finds

* **Minification.** Code was reduced semi-automatically: JavaScript through uglifyjs, shaders via a custom minifier script. That was enough to fit within the size limit.

* **Adaptive resolution scaling.** The game dynamically adjusts render size to keep FPS above 55.

* **ASCII levels.** Entire maps were encoded as ASCII strings, easy to tweak and test quickly.

* **Cat AI.** Two distinct behaviors: black cats charge and zigzag, white cats orbit and drain health if stared at.

* **Checkpoint system.** Every three levels stored progress, reducing frustration.

* **Shader-driven models.** Cats, doors, and idols were built from SDF primitives directly in GLSL.

* **Boss fight.** The *ChornoCot* avatar cycled phases with orbit, gaze attacks, and bullet-hell patterns.

## Lessons Learned

* **Optimization is constant.** Every new feature meant reworking performance.
* **Keep it simple.** Focus on the core mechanic instead of chasing extras.
* **AI is useful but limited.** It helps brainstorm and code, but breaks when overloaded.
* **Version control saves panic.** Always commit working code.
* **Game design is about feel.** The white/black cat twist was confusing yet memorable.

## Next Steps / Ideas

* Game menu and settings screen.

* Expansion: Episode 2, *ChornoCot Returns*.

* Better cats (models, turning, behavior).

* More sound (attacks, meows, music, ambient).

* Larger maps, multiple connected rooms, hidden endings.

* Additional bosses, towers, scripted quests.

## Media

![Preview 320x320](https://github.com/dkozhukhar/cat-shooter/blob/main/preview_img/preview_320x320_50kb.png)

## Links

* [Play Cat Shooter Ritual Catacombs (js13k 2025 entry)](https://js13kgames.com/2025/games/cat-shooter-ritual-catacombs)
* [Source code on GitHub](https://github.com/dkozhukhar/cat-shooter/)
* [My earlier 2019 entry: Jet Back Gravity](https://js13kgames.com/2019/games/jet-back-gravity)

## Closing

The whole process took about one month of free time (\~20–40 hours). The result: a short 3D shooter with atmosphere, cats, and a boss fight. Imperfect, but complete. For me, the big success was not the game length, but the learning curve — GL, shaders, a touch of AI, and pipelines.

---

**P.S.** Every level has hidden transitions behind false walls, originally made just to test level switching but left in place. Some levels also contain secret spots. In the final room there is one more hidden passage, leading to an alternate ending. At one point I thought of putting extra levels there, but decided it would be too unclear for this jam.
