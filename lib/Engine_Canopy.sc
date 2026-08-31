// Engine_Canopy
// four modal/pinged-filter voices, DynKlank-style but hand-built so strike
// position and structure can be re-shaped live. see docs/canopy-spec.md
// §8 for the woodiness recipe, §9 for the build order.
//
// build phase 4 added the S-cell exciters (§2.4), the generic audio-rate
// patch matrix (§7.3's \patch_aa / \patch_ak), and the stream inputs on the
// voice synth. build phase 5 added \wl_heartwood, the continuous half of the
// §2.5 diffusion lattice. 5b added `glide` and the per-voice detune `drift`.
//
// build phase 6 -- the re-cut -- changes three things here:
//
//   * six voices become four, each with ONE modulation input (the M socket)
//     instead of three anonymous ones, and a `modBalance` deciding what a
//     stream landing there does: inject into the resonator at 0, bend the
//     body at 1.
//   * every voice now also writes its own signal to a tap bus, scaled by
//     `tapLevel` -- the O socket. that is what makes voice<->voice feedback a
//     cable rather than a phase-7 promise.
//   * ten exciters become twenty. the second ten are aimed squarely at a kit:
//     clicks, metals, scrapes, impacts, air.
//
// the Grain macro is gone with it: the voice page (§5.5) exposes structure,
// damping, brightness, drive, strike position, decay, tune and level
// individually, so there is nothing left for a macro to hide.
//
// build phase 7, the re-name: Canopy -- the shared plate/hall reverb -- and
// the output Compressor are both gone. what replaces Canopy on the global
// page is literal rather than an effect: an always-on loop of a real rain
// recording (\wl_rain, loaded async by rain_load once Lua knows its path),
// mixed dry into the output at whatever level `rain_volume` asks for, and
// fed continuously into every voice's resonator as excitation at whatever
// depth `rain_excite` asks for -- the wood actually being rained on, rather
// than a reverb pretending to be weather.
//
// the grid overhaul changes \woodland_fx more than anything since build
// phase 6: there is no automatic mix left at all. a voice's or percussion
// cell's own tap bus, an exciter, and a heartwood node's emergence all used
// to reach \woodland_fx directly, panned at a fixed compile-time position
// per source; now NONE of them do, and \woodland_fx reads only a bank of
// sixteen `outBus` channels (the Output row) that ordinary patch cables have
// to be routed into for anything to be heard at all. discrete choke (a
// pulse on the old M socket) is gone too -- every pulse strikes a voice now
// -- so \woodland_voice lost its choke envelope along with `tapLevel`'s
// separate output-level knob; loudness at each Output-row position is
// purely that cable's own gain. exciters trimmed from twenty to six, the
// heartwood lattice from an eight-node ring to a four-node chain.

Engine_Canopy : CroneEngine {
	var gSrc, gPatch, gVoice, gTap, gFx;
	var patchBus, excMeterBus, rainBus;
	var voiceSynths;
	var gSynths;
	var excSynths;
	var patchSynths;
	var heartSynth;
	var fxSynth;
	var excMeterSynth;
	var rainBuf;
	var rainSynth;

	// name, freq, structureBase (0..1, ignored when oddOnly=1), oddOnly, dampBase, decay
	// §8 "per-voice defaults" table. keep freq/structureBase/dampBase/decay in
	// step with topology.lua's VOICES table -- the Lua side sweeps the sound
	// page's knobs *around* these numbers, so they have to be the same numbers.
	//
	// nested arrays inside a literal array are written WITHOUT their own `#`
	// -- sclang's grammar only allows the `#` on the outermost one, and an
	// inner `#[` is a syntax error that fails the whole class library.
	classvar voiceDefs = #[
		[\oak,   55,  0.55, 0, 1.1, 1.2],
		[\hazel, 220, 0.95, 0, 1.3, 0.28],
		[\alder, 98,  0.5,  1, 0.8, 1.6],
		[\rowan, 330, 0.75, 0, 0.6, 1.8]
	];

	// §2.4 exciter table, in the same order as topology.lua's E_CELLS list --
	// index i here IS the E cell's `index` field on the Lua side. flat array,
	// no nesting -- sclang's grammar only accepts a *literal* on the right of
	// a classvar `=`, and a bare `[...]` here is a parse error that takes the
	// whole class library down with it. trimmed to six for the grid overhaul
	// (was twenty) -- a spread of textures rather than the full kit.
	classvar excDefs = #[
		\wl_exc_bracken, \wl_exc_ember, \wl_exc_gorse,
		\wl_exc_windfall, \wl_exc_mistle, \wl_exc_wisp
	];

	// §2.7b percussion cells -- simple drum voices, not the modal resonator
	// bank above. `kind` per index matches topology.lua's GVOICE_CELLS order:
	// \wl_g_ping (pinged resonant filter) for the first three (the panel's
	// "F" percussion cells), \wl_g_noise (enveloped filtered noise) for the
	// last three (the "N" cells).
	classvar gDefs = #[
		\wl_g_ping, \wl_g_ping, \wl_g_ping,
		\wl_g_noise, \wl_g_noise, \wl_g_noise
	];

	classvar nVoices = 4, nExc = 6, nG = 6, nH = 4, nOut = 16;

	// offsets into the single `patchBus` block (§7.3's separate bus families
	// collapsed into one allocation so the Lua side only needs to add an
	// offset, not track many bus objects). spec calls the modulation buses
	// "control buses"; they are implemented here as audio buses instead,
	// because Out.kr *overwrites* a bus each block while Out.ar *adds* -- and
	// several cables landing on one voice's mod path need to sum, not fight.
	// keep these numbers in sync with bridge.lua's `bridge.BUS` table.
	//
	// the grid overhaul added `gvoiceOutBase` (the percussion cells needed an
	// addressable tap once they stopped reaching the speakers automatically)
	// and `outBase` (the Output row -- nothing reaches `woodland_fx` at all
	// any more except through an ordinary patch cable into one of these
	// sixteen fixed-pan buses).
	classvar excBase = 0, colourModBase = 6, modInBase = 12,
		voiceOutBase = 16, gvoiceOutBase = 20, heartInBase = 26,
		heartOutBase = 30, outBase = 34, patchTotal = 50;

	*new { arg context, doneCallback;
		^super.new(context, doneCallback);
	}

	alloc {
		var server = context.server;
		var gateMul;

		gSrc = Group.new(context.xg);
		gPatch = Group.after(gSrc);
		gVoice = Group.after(gPatch);
		gTap = Group.after(gVoice);
		gFx = Group.after(gTap);

		// see the classvar block above for the sub-ranges packed in here.
		// every voice and every percussion cell writes ONLY to its own tap
		// slot in here now -- the grid overhaul removed the automatic mix
		// that used to also read voiceBus/gBus directly, so those two
		// allocations are gone; a voice or GVOICE cell is only ever heard
		// through an Output-row cable, same as everything else.
		patchBus = Bus.audio(server, patchTotal);
		// §7.4 metering back-channel: one control-rate channel per exciter,
		// read synchronously off the shared-memory server interface by the
		// addPoll funcs below -- no OSC round trip, so this is cheap even at
		// full count.
		excMeterBus = Bus.control(server, nExc);
		// the always-on rain ambience (§4.1 Rain/Excite): a stereo bus, always
		// allocated, silent until rain_load's buffer finishes loading and
		// \wl_rain starts writing to it. every voice and the fx stage read it
		// with plain In.ar -- both live in groups after gSrc, so a block with
		// nothing writing here is just a block of zeros, not stale data.
		rainBus = Bus.audio(server, 2);

		SynthDef(\woodland_voice, {
			arg tapOut=0, t_trig=0, force=0.6, hardness=0.5, position=0.15,
				freq=110, damp=0.8, bright=0.5, drive=0.2, structure=0.5,
				oddOnly=0, decayBase=2.0, amp=1.0, modes=6,
				modIn=0, modBalance=0.5,
				fmRatio=2.0, fmDepth=0, noiseTune=0, exciteQ=0.35,
				glide=0.02, driftDepth=0.06, driftRate=0.07, driftSeed=0,
				bendAmt=0, rainIn=0, rainExcite=0;

			var harmonicRatio = [1, 2, 3, 4, 5, 6];
			var barRatio = [1, 2.756, 5.404, 8.933, 13.34, 18.64];

			// the collapsed point's stream half (was the M socket). one
			// input, one knob (Balance, §5.5). at balance 0 the stream is
			// excitation -- it goes into the resonator alongside the voice's
			// own strike burst. at balance 1 it is a control signal on the
			// body: damping, brightness and a little structure. discrete
			// choke (a pulse landing here) is gone with the socket that used
			// to carry it -- every pulse strikes now (dispatch.lua).
			var modStream = In.ar(modIn, 1);
			var inject = modStream * (1 - modBalance.clip(0, 1));
			var bend = modStream * modBalance.clip(0, 1);

			var structBend = bend * 0.3;
			var structureEff = (structure + structBend).clip(0, 1.3);
			var dampMod = bend * 0.5;
			var brightMod = bend * 0.5;

			// §8.3: a noise-burst exciter, never a raw impulse. hard mallet
			// (hardness -> 1) = brighter, shorter burst. pink, not white --
			// warmer, less hiss-y -- and independently tuneable: noiseTune
			// (bipolar, +-1 octave) and exciteQ sit on top of hardness's own
			// brightness/duration mapping rather than replacing it.
			var burstDur = 0.008 - (hardness.clip(0, 1) * 0.006);
			var bpFreq = (800 + (hardness.clip(0, 1) * 5200)) * (2 ** noiseTune);
			// .ar, not .kr: burstDur is 2-8 ms and a control period is ~1.3 ms
			// at norns' block size, so a kr envelope quantises the whole burst
			// to one or two steps and `hardness` stops shortening it at all.
			var env = EnvGen.ar(Env.perc(0.0003, burstDur), t_trig);
			var exc = BPF.ar(PinkNoise.ar(1), bpFreq, exciteQ) * env * force;
			// §4.1 rain_excite: the same always-on rain ambience every voice
			// can be cabled to nothing and still hear -- a mono sum of the
			// stereo loop, scaled down for headroom (the wav is a full-level
			// recording, not a designed exciter burst) and by the knob
			// itself. 0 (the default) is a no-op.
			// squared, not linear: unlike the burst exciter, this is a
			// *continuous* signal into the mode bank's Ringz below, so it
			// sits there and rings up to Ringz's steady-state resonant gain
			// (which grows with each mode's decay time) instead of just
			// decaying after one brief hit like the burst exciter does. that
			// makes this knob's low end far more sensitive than a linear
			// multiply looks like it should be -- 0.03 already reads as a
			// sustained, well-fed resonance, not a token amount. squaring
			// buys back a usable quiet range without changing full-up.
			var rainSig = (Mix.ar(In.ar(rainIn, 2)) * 0.5)
				* rainExcite.clip(0, 1).squared * 0.7;
			var totalExc = exc + (inject * 0.8) + rainSig;

			// §8.5: amplitude-dependent pitch drop -- the "thunk" of a hard hit.
			var pitchDrop = 1 - (force.clip(0, 1) * 0.02);

			// §2.6, the continuous half of the grove. two things happen to
			// `freq` before it reaches the mode bank:
			//
			// `glide` is portamento on whatever pitch Lua last sent, so a
			// field stepping to a new degree is heard as a move rather than
			// as a discontinuity in a bank of already-ringing resonators. a
			// discrete mode asks for ~10 ms (lands on the strike); a
			// continuous one asks for hundreds (heard as a slide).
			//
			// `drift` is the detune wander, and it is generated here rather
			// than in Lua for the obvious reason: a few cents moving
			// continuously is far too fine to push over OSC without either
			// flooding it or stepping audibly. three incommensurate slow
			// shapes summed, so it never repeats; driftSeed offsets the
			// phases so no two voices breathe together.
			var driftA = SinOsc.kr(driftRate * 0.31, driftSeed * 1.7);
			var driftB = SinOsc.kr(driftRate * 0.53, (driftSeed * 2.9) + 1.1);
			var driftC = LFNoise2.kr((driftRate * 0.83).max(0.001));
			var drift = ((driftA * 0.5) + (driftB * 0.3) + (driftC * 0.4)) / 1.2;

			// §5.5 Bend: a short pitch drop on top of everything else, fired by
			// the same t_trig as the strike -- an 808's glide from a couple of
			// octaves up down to the fundamental, if you turn it up that far.
			// \exp can't reach a literal 0, so the envelope settles on a floor
			// close enough to it that the leftover detuning (~0.003 semitones)
			// is inaudible -- the same trick the M-socket choke envelope below
			// uses. bendAmt=0 makes the exponent 0 regardless of the envelope,
			// so this is a no-op until the knob is turned up.
			var bendTime = 0.06;
			var bendFloor = 0.001;
			var bendEnv = EnvGen.ar(Env([1, bendFloor], [bendTime], \exp), t_trig);
			var bendOctaves = 2;
			var bendRatio = 2 ** (bendEnv * bendAmt.clip(0, 1) * bendOctaves);

			var freqBase = Lag.kr(freq, glide.clip(0, 4))
				* (drift * driftDepth).midiratio
				* bendRatio;

			// FM: every voice can be frequency-modulated (engine-level -- not
			// yet a patchable cable). fmDepth=0 is a no-op, so nothing about
			// the existing sound changes until it's turned up. one shared
			// modulator ahead of the mode ratios, so all six modes move
			// together instead of detuning against each other.
			var fmOsc = SinOsc.ar((freqBase * fmRatio).max(0.1)) * fmDepth;
			var freqFM = freqBase * (1 + fmOsc);

			var modeSig = Mix.fill(6, { |i|
				var n = i + 1;
				// §8.1: morph harmonic -> free-free bar via `structure`;
				// Alder overrides with an odd-only ratio set ("hollow tube").
				var ratio = Select.kr(oddOnly, [
					harmonicRatio[i] + ((barRatio[i] - harmonicRatio[i]) * structureEff),
					(2 * n) - 1
				]);
				var mfreq = freqFM * ratio * pitchDrop;
				// §8.2: frequency-dependent damping -- high modes die fast.
				// the ceiling is above the longest decayBase the sound page
				// can ask for (Rowan's 1.8 s default, x4 at the top of the
				// knob), so the ring time the page reads out is the one you
				// actually hear.
				var mdecay = (decayBase * (ratio ** (damp + dampMod).neg)).clip(0.02, 30);
				// §8.4: strike position comb-notches modes with a node there.
				var mamp = (pi * position * n).sin;
				var active = i < modes;
				Ringz.ar(totalExc, mfreq, mdecay) * mamp * active;
			});

			// a plain, tuneable, pinged resonant-filter bank plus a gentle
			// tanh. the tanh is the DC-blocked, soft-saturating, limited
			// safety net §6 wants now that voice<->voice feedback is a real
			// cable ("do not prevent the loop"), dialled back to a x0.8 drive
			// so it no longer colours the tone on its own.
			var driven = (modeSig * (1 + (drive * 0.8))).tanh;
			var toned = LPF.ar(driven, 400 + ((bright + brightMod).clip(0, 1) * 9000));

			var sig = Limiter.ar(LeakDC.ar(toned), 0.95) * amp * 0.35;

			// the collapsed point's only destination: its own patchBus tap.
			// there is no separate output-level knob any more -- how loud
			// this voice is heard (if at all) is purely the gain on whatever
			// cable reaches an Output-row cell from here (dispatch.lua).
			Out.ar(tapOut, sig);
		}).add;

		// §2.7b percussion cells (the panel's F/N cells). much smaller than
		// \woodland_voice -- a single ping or a single enveloped noise burst
		// rather than a six-mode bank -- but the same six knobs either kind
		// answers to: t_trig/force (the strike), freq (Pitch), decay (Decay,
		// straight onto the envelope/ring time -- no frequency-dependent
		// damping bank to interact with, unlike the corner voices), tone,
		// punch, drive, amp. `out` is this cell's own patchBus tap (the grid
		// overhaul's `gvoiceOutBase` range) -- there is no separate always-on
		// mix bus any more, so this is the only place its audio goes.
		//
		// \wl_g_ping: a short noise click (its colour and length set by
		// punch) rings a two-partial Ringz bank -- the fundamental at freq,
		// plus a detuned, faster-decaying second partial mixed in by tone,
		// which is what keeps a ping from reading as a pure sine.
		SynthDef(\wl_g_ping, {
			arg out=0, t_trig=0, force=0.6, freq=180, decay=0.28, tone=0.5,
				punch=0.3, drive=0.2, amp=0.8;
			var p = punch.clip(0, 1);
			var clickDur = 0.0002 + (0.006 * (1 - p));
			var click = EnvGen.ar(Env.perc(0.0002, clickDur), t_trig) * force;
			var exc = (WhiteNoise.ar(1) * p) + (PinkNoise.ar(1) * (1 - p));
			var burst = exc * click;
			var d = decay.clip(0.01, 8);
			var t = tone.clip(0, 1);
			var ring = Ringz.ar(burst, freq.clip(20, 12000), d)
				+ (Ringz.ar(burst, (freq * 2.756).clip(20, 18000), d * 0.4) * t * 0.5);
			var driven = (ring * (1 + (drive.clip(0, 1) * 1.5))).tanh;
			var sig = Limiter.ar(LeakDC.ar(driven), 0.95) * amp * 0.6;
			Out.ar(out, sig);
		}).add;

		// \wl_g_noise: an envelope (attack shaped by punch, length by decay)
		// gates a band of noise whose colour (brown<->white) and bandwidth
		// tone crossfades -- narrower and browner at tone=0, wider and
		// whiter at tone=1 -- centred on freq.
		SynthDef(\wl_g_noise, {
			arg out=0, t_trig=0, force=0.6, freq=1500, decay=0.15, tone=0.5,
				punch=0.3, drive=0.2, amp=0.8;
			var t = tone.clip(0, 1);
			var atk = 0.0004 + (0.012 * (1 - punch.clip(0, 1)));
			var env = EnvGen.ar(Env.perc(atk, decay.clip(0.01, 4)), t_trig) * force;
			var noiseMix = (WhiteNoise.ar(1) * t) + (BrownNoise.ar(1) * (1 - t));
			var band = BPF.ar(noiseMix, freq.clip(20, 18000), 0.15 + (0.45 * (1 - t)));
			var burst = band * env;
			var driven = (burst * (1 + (drive.clip(0, 1) * 1.5))).tanh;
			var sig = Limiter.ar(LeakDC.ar(driven), 0.95) * amp * 0.6;
			Out.ar(out, sig);
		}).add;

		// the grid overhaul's Output row (§2's `O` cells): the only place
		// audio reaches the speakers, and the only thing left in this synth
		// that reads anything other than the rain bus. by default nothing is
		// patched into any of the sixteen `outBus` channels, so a fresh
		// patch is silent until the player cables a voice, a GVOICE cell, an
		// exciter or a heartwood node to one -- there is no automatic mix
		// left at all, which is the entire point ("by default none of the
		// voices are wired up to any outputs").
		//
		// each of the sixteen channels has a FIXED pan position, hard left
		// at channel 0 to hard right at channel 15 (keep this identical to
		// topology.lua's `pan = -1 + 2*(i-1)/15` for O cell i) -- position
		// along the row is what sets pan, not a knob. cabling one source to
		// several O cells sums it at each position it reaches, each at that
		// cable's own gain (patch.lua's ordinary bipolar gain), the same way
		// several cables landing on one mod-path bus already sum.
		SynthDef(\woodland_fx, {
			arg outBus=0, out=0, level=0.8, rainIn=0, rainVol=0;
			var chans = In.ar(outBus, nOut);
			var panPos = Array.fill(nOut, { |i| -1 + (2 * i / (nOut - 1)) });
			var dry = Mix.ar(Array.fill(nOut, { |i| Pan2.ar(chans[i], panPos[i]) }));
			// rainVol gets the same correction as rain_excite above: squared
			// for a usable low end, and the 0.35 headroom factor every
			// voice's own output already carries (Limiter... * amp * 0.35)
			// so the full-level Rain.wav doesn't sit hotter in the mix than
			// a voice at the same knob position.
			var rainDry = In.ar(rainIn, 2) * rainVol.clip(0, 1).squared * 0.35;
			var sig = (dry + rainDry) * level;
			Out.ar(out, sig);
		}).add;

		// shared gate envelope for every exciter (§2.4: "an S cell is
		// continuous until a pulse is cabled into it. a pulse cable turns the
		// exciter into an enveloped grain, fired by that pulse"). `gated`
		// flips that switch; `t_gate` fires one grain while gated.
		// `decay` (E3 on an S cell, §4.2) is a plain multiplier on every time
		// constant the exciter has: the grain envelope here, and -- for the
		// recipes that have a tail of their own -- that tail as well. the
		// 0..1 knob is mapped to this multiplier on the Lua side, so the
		// engine only ever sees a ratio.
		gateMul = { |tGate, gated, dur, amp, decay|
			var env = EnvGen.ar(Env.perc(0.002, (dur * decay).clip(0.02, 4)), tGate) * amp;
			Select.ar(gated, [DC.ar(1), env]);
		};

		// §2.4 exciter recipes. each is deliberately its own thing -- these
		// are noise colours and textures, not one macro. `colour` (E2, §4.2)
		// is the one thing that matters about each; the exact curve is a
		// sound-design call, tune by ear once this is on hardware. `c` folds
		// in `colourModIn`, which is where S<->S cross-modulation, a cabled
		// pitch field and a voice's own output all land.
		//
		// InFeedback, not In: the colour-mod buses are written by patch
		// synths in gPatch, which runs AFTER gSrc, and In.ar returns silence
		// for a bus nothing has touched yet this cycle.
		//
		// every exciter also takes fmRatio/fmDepth (§ FM addendum, same
		// engine-level deal as the voice's fmDepth=0 no-op): each one's own
		// natural "frequency" parameter gets an audio-rate
		// `* (1 + SinOsc.ar(base * fmRatio) * fmDepth)` on top of what Colour
		// already does to it.

		SynthDef(\wl_exc_bracken, { arg out=0, colour=0.5, colourModIn=0,
				gated=0, t_gate=0, gateDur=0.15, gateAmp=0.8, fmRatio=2.0, fmDepth=0,
				decay=1.0;
			var c = (colour + InFeedback.ar(colourModIn, 1)).clip(0, 1);
			var base = 500 + (c * 4000);
			var fm = SinOsc.ar(base * fmRatio) * fmDepth;
			var bp = BPF.ar(WhiteNoise.ar(1), base * (1 + fm), 0.5);
			var crackle = Decay2.ar(Dust.ar(15 + (c * 45)), 0.001, 0.02 * decay) * WhiteNoise.ar(1);
			var sig = (bp * 0.6) + (crackle * 0.5);
			Out.ar(out, sig * gateMul.value(t_gate, gated, gateDur, gateAmp, decay) * 0.3);
		}).add;

		SynthDef(\wl_exc_gorse, { arg out=0, colour=0.5, colourModIn=0,
				gated=0, t_gate=0, gateDur=0.15, gateAmp=0.8, fmRatio=2.0, fmDepth=0,
				decay=1.0;
			var c = (colour + InFeedback.ar(colourModIn, 1)).clip(0, 1);
			var base = 3500 + (c * 5000);
			var fm = SinOsc.ar(base * fmRatio) * fmDepth;
			var sig = BPF.ar(WhiteNoise.ar(1), base * (1 + fm), 0.06);
			Out.ar(out, sig * gateMul.value(t_gate, gated, gateDur, gateAmp, decay) * 0.3);
		}).add;

		SynthDef(\wl_exc_ember, { arg out=0, colour=0.5, colourModIn=0,
				gated=0, t_gate=0, gateDur=0.15, gateAmp=0.8, fmRatio=2.0, fmDepth=0,
				decay=1.0;
			var c = (colour + InFeedback.ar(colourModIn, 1)).clip(0, 1);
			var base = 4 + (c * 40);
			var fm = SinOsc.ar(base.max(0.1) * fmRatio) * fmDepth;
			var trig = Dust.ar((base * (1 + fm)).max(0.1));
			var sig = Decay2.ar(trig, 0.0005, (0.03 + (c * 0.05)) * decay) * WhiteNoise.ar(1);
			Out.ar(out, sig * gateMul.value(t_gate, gated, gateDur, gateAmp, decay) * 0.3);
		}).add;

		SynthDef(\wl_exc_windfall, { arg out=0, colour=0.5, colourModIn=0,
				gated=0, t_gate=0, gateDur=0.15, gateAmp=0.8, fmRatio=2.0, fmDepth=0,
				decay=1.0;
			var c = (colour + InFeedback.ar(colourModIn, 1)).clip(0, 1);
			var trig = Dust.ar(2 + (c * 10));
			var genv = EnvGen.ar(Env.perc(0.001, (0.04 + (c * 0.08)) * decay), trig);
			var base = 900 + (c * 3000);
			var fm = SinOsc.ar(base * fmRatio) * fmDepth;
			var sig = BPF.ar(WhiteNoise.ar(1), base * (1 + fm), 0.3) * genv;
			Out.ar(out, sig * gateMul.value(t_gate, gated, gateDur, gateAmp, decay) * 0.3);
		}).add;

		SynthDef(\wl_exc_mistle, { arg out=0, colour=0.5, colourModIn=0,
				gated=0, t_gate=0, gateDur=0.15, gateAmp=0.8, fmRatio=2.0, fmDepth=0,
				decay=1.0;
			var c = (colour + InFeedback.ar(colourModIn, 1)).clip(0, 1);
			var trig = Dust.ar(1 + (c * 4));
			var fenv = EnvGen.ar(Env([1800 + (c * 1500), 3200 + (c * 2000), 2200], [0.02, 0.06], \exp), trig);
			var aenv = EnvGen.ar(Env.perc(0.005, 0.09 * decay), trig);
			var fm = SinOsc.ar(fenv * fmRatio) * fmDepth;
			var sig = SinOsc.ar(fenv * (1 + fm)) * aenv;
			Out.ar(out, sig * gateMul.value(t_gate, gated, gateDur, gateAmp, decay) * 0.3);
		}).add;

		// control-rate by spec ("slow wandering random walk, control-rate");
		// K2A.ar upsamples it onto the shared audio-rate exciter bus so it
		// can sum and gate the same way as the others.
		SynthDef(\wl_exc_wisp, { arg out=0, colour=0.5, colourModIn=0,
				gated=0, t_gate=0, gateDur=0.15, gateAmp=0.8, fmRatio=2.0, fmDepth=0,
				decay=1.0;
			var c = (colour + InFeedback.ar(colourModIn, 1)).clip(0, 1);
			var base = 0.3 + (c * 2);
			// stays control-rate throughout, like the rest of Wisp -- an
			// audio-rate FM term here would wiggle faster than LFNoise1.kr
			// ever samples it and do nothing audible.
			var fm = SinOsc.kr(base * fmRatio) * fmDepth;
			var sig = K2A.ar(LFNoise1.kr((base * (1 + fm)).max(0.05)).range(-1, 1));
			Out.ar(out, sig * gateMul.value(t_gate, gated, gateDur, gateAmp, decay) * 0.3);
		}).add;

		// §2.5 the heartwood. "not a bus. a diffusion lattice." trimmed from
		// a ring of 8 to a chain of 4 for the grid overhaul -- each node
		// still a short delay line that hands what reaches it on to its
		// neighbours, quieter and later. streams patched into a node arrive
		// on heartInBase+i; what emerges at a node is on heartOutBase+i, and
		// that is what a cable out of a heartwood cell taps.
		//
		// adjacency duplicates topology.lua's 4-node chain, taproot first.
		// the two lists have to agree; there is no way to check that from
		// this side.
		//
		// InFeedback on the injection buses, and LocalIn/LocalOut for the
		// lattice itself: this synth lives in gSrc, which runs *before* the
		// gPatch synths that write the injection buses, and the lattice is a
		// cyclic graph -- there is no node order that makes a chain acyclic
		// once shortcut cables are patched onto it. one block of latency
		// either way, which at 64 samples is inaudible.
		//
		// the /2.5 on the pass gain is what keeps the chain stable -- fewer
		// nodes than the original ring, but the same headroom margin holds
		// (a chain's mean degree is lower than a ring's, so if anything this
		// is more conservative than it needs to be).
		SynthDef(\wl_heartwood, {
			arg inBus=0, outBus=0, c0=0.5, c1=0.5, c2=0.5, c3=0.5;

			var conds = [c0, c1, c2, c3];
			var hNbr = [[1], [0, 2], [1, 3], [2]];
			var inj = InFeedback.ar(inBus, nH);
			var fb = LocalIn.ar(nH);

			var emerge = Array.fill(nH, { |i|
				var arriving = hNbr[i].collect({ |j| fb[j] }).sum;
				LeakDC.ar(inj[i] + arriving).tanh;
			});

			// what each node passes on: its own signal, delayed and attenuated
			// by its own conductance. keep this mapping identical to the
			// HOP_MIN/HOP_MAX and LOSS_MIN/LOSS_MAX pair in heartwood.lua, or
			// one node's knob will mean two different things to the pulse and
			// the stream halves of the same lattice.
			var passed = Array.fill(nH, { |i|
				var c = conds[i].clip(0, 1);
				var hop = 0.35 - (c * 0.30);
				var loss = 0.10 + (c * 0.80);
				DelayC.ar(emerge[i], 0.4, hop) * (loss / 2.5);
			});

			LocalOut.ar(passed);
			Out.ar(outBus, emerge);
		}).add;

		// §7.3's generic audio-rate patch matrix. one synth per live cable
		// that means something continuous (§6): a stream into a voice's M
		// socket is a straight pass (\wl_patch_aa); anything landing on a
		// colour-mod bus follows the source's amplitude first
		// (\wl_patch_ak). `src`/`dst` are absolute bus numbers computed on
		// the Lua side (bridge.BUS) and fixed at creation.
		//
		// InFeedback on the source, not In. these synths live in gPatch,
		// which runs before gVoice, so a cable whose source is a voice's own
		// output tap (the O socket) would read silence with plain In.ar --
		// and O->M is now a legal, and the most interesting, cable. one block
		// of latency on every cable rather than a node-order rule nobody can
		// see: 1.5 ms at norns' block size, and it makes the whole matrix
		// order-independent by construction.
		SynthDef(\wl_patch_aa, { arg src=0, dst=0, gain=0.6;
			Out.ar(dst, InFeedback.ar(src, 1) * gain);
		}).add;

		SynthDef(\wl_patch_ak, { arg src=0, dst=0, gain=0.6;
			Out.ar(dst, LPF.ar(Amplitude.ar(InFeedback.ar(src, 1), 0.01, 0.1), 20) * gain);
		}).add;

		// §7.4: an envelope follower per exciter, plain In.ar (not
		// InFeedback) because this lives in gTap, which runs after gSrc --
		// the exciters have already written this block's audio by the
		// time it reads them. one control-rate channel out per exciter, for
		// the addPoll funcs below to read synchronously.
		SynthDef(\wl_exc_meter, { arg in=0, out=0;
			var sig = In.ar(in, nExc);
			Out.kr(out, Amplitude.kr(sig, 0.005, 0.2));
		}).add;

		// the always-on rain ambience (§4.1). a plain looping stereo playback
		// of whatever rain_load hands it -- no envelope, no gate, because the
		// whole point is that it is always running and rain_volume/rain_excite
		// are the only things that ever make it audible or felt.
		SynthDef(\wl_rain, { arg out=0, bufnum=0;
			var sig = PlayBuf.ar(2, bufnum, BufRateScale.kr(bufnum), loop: 1);
			Out.ar(out, sig);
		}).add;

		server.sync;

		voiceSynths = Array.newClear(nVoices);
		voiceDefs.do({ |def, i|
			voiceSynths[i] = Synth.new(\woodland_voice, [
				\tapOut, patchBus.index + voiceOutBase + i,
				\freq, def[1],
				\structure, def[2],
				\oddOnly, def[3],
				\damp, def[4],
				\decayBase, def[5],
				\modIn, patchBus.index + modInBase + i,
				\rainIn, rainBus.index
			], gVoice);
		});

		// §2.7b: always-on like the four corner voices, not lazily allocated
		// like the exciters -- these are drums, struck directly, not streams
		// that only exist while cabled. `out` is this cell's own patchBus
		// tap (gvoiceOutBase) -- the same bus family a voice's `tapOut`
		// uses, since the grid overhaul removed the always-on mix bus this
		// used to write to instead. gvoice.lua's init() pushes every cell's
		// real freq/decay/tone/punch/drive/amp right after this, the same
		// way voice.lua's init() does for voiceSynths.
		gSynths = Array.newClear(nG);
		gDefs.do({ |def, i|
			gSynths[i] = Synth.new(def, [\out, patchBus.index + gvoiceOutBase + i], gVoice);
		});

		excSynths = Array.newClear(nExc);
		patchSynths = Dictionary.new;

		// in gSrc, so the emergence buses are already written by the time the
		// gPatch cables that tap them run this block; the injection buses it
		// reads are the ones gPatch wrote last block (hence InFeedback above).
		// unlike the exciters this is not lazily allocated -- it is the wood
		// itself, it costs nH delay lines, and a lattice that only exists
		// once something is patched into it cannot ring on after the cable is
		// pulled, which is precisely the thing §2.5 wants it to do.
		heartSynth = Synth.new(\wl_heartwood, [
			\inBus, patchBus.index + heartInBase,
			\outBus, patchBus.index + heartOutBase
		], gSrc);

		// \woodland_fx reads only the Output row now (outBase) -- see its
		// SynthDef comment above. gFx runs after gPatch (the group that
		// writes outBus), so a plain In.ar there sees this block's data.
		fxSynth = Synth.new(\woodland_fx, [
			\outBus, patchBus.index + outBase,
			\out, context.out_b.index,
			\rainIn, rainBus.index
		], gFx);

		// gTap: after gVoice (so the exciter meters below share the group
		// this file has kept reserved for taps), reading the exciters' own
		// audio written earlier this block by gSrc.
		excMeterSynth = Synth.new(\wl_exc_meter, [
			\in, patchBus.index + excBase,
			\out, excMeterBus.index
		], gTap);

		// §7.4: one scalar poll per exciter, named to match its E-cell
		// index (bridge.lua / topology.lua's `cell.index`, 0-based) so
		// exciter.lua can start them by number without a name table on
		// either side. getControlBusValue reads the shared-memory control
		// bus directly -- no OSC round trip.
		nExc.do({ |i|
			this.addPoll(("exc_lvl_" ++ i).asSymbol, {
				server.getControlBusValue(excMeterBus.index + i)
			});
		});

		// strike(voice, force, hardness, position)
		this.addCommand("strike", "ifff", { |msg|
			var v = msg[1].asInteger;
			if (v >= 0 and: { v < nVoices }) {
				voiceSynths[v].set(
					\force, msg[2], \hardness, msg[3], \position, msg[4], \t_trig, 1
				);
			};
		});

		this.addCommand("voice_pitch", "if", { |msg|
			var v = msg[1].asInteger;
			if (v >= 0 and: { v < nVoices }) { voiceSynths[v].set(\freq, msg[2]) };
		});

		// voice_glide(voice, seconds) -- §2.6: portamento on voice_pitch.
		// grove.lua sends it just ahead of a pitch, and only when it changes.
		this.addCommand("voice_glide", "if", { |msg|
			var v = msg[1].asInteger;
			if (v >= 0 and: { v < nVoices }) { voiceSynths[v].set(\glide, msg[2]) };
		});

		// voice_drift(voice, depthSemitones, rateHz, seed) -- §2.6: the
		// always-on detune wander. depth is small by design; grove.lua raises
		// it a little for voices with a wide field cabled to them.
		this.addCommand("voice_drift", "ifff", { |msg|
			var v = msg[1].asInteger;
			if (v >= 0 and: { v < nVoices }) {
				voiceSynths[v].set(
					\driftDepth, msg[2], \driftRate, msg[3], \driftSeed, msg[4]
				);
			};
		});

		// the eight knobs of §5.5's voice page. no macro in front of them any
		// more -- voice.lua maps each 0..1 knob to the real unit below and
		// sends it here, so what the page reads out is what the synth has.

		// voice_decay(voice, seconds) -- the resonator's own ring time,
		// straight onto `decayBase`: the mode bank's frequency-dependent
		// damping still shortens the high modes relative to it, so the voice
		// keeps its character and only its length changes.
		this.addCommand("voice_decay", "if", { |msg|
			var v = msg[1].asInteger;
			if (v >= 0 and: { v < nVoices }) {
				voiceSynths[v].set(\decayBase, msg[2].clip(0.02, 30));
			};
		});

		this.addCommand("voice_structure", "if", { |msg|
			var v = msg[1].asInteger;
			if (v >= 0 and: { v < nVoices }) {
				voiceSynths[v].set(\structure, msg[2].clip(0, 1.3));
			};
		});

		this.addCommand("voice_damp", "if", { |msg|
			var v = msg[1].asInteger;
			if (v >= 0 and: { v < nVoices }) { voiceSynths[v].set(\damp, msg[2]) };
		});

		this.addCommand("voice_bright", "if", { |msg|
			var v = msg[1].asInteger;
			if (v >= 0 and: { v < nVoices }) { voiceSynths[v].set(\bright, msg[2]) };
		});

		this.addCommand("voice_pos", "if", { |msg|
			var v = msg[1].asInteger;
			if (v >= 0 and: { v < nVoices }) { voiceSynths[v].set(\position, msg[2]) };
		});

		// voice_bend(voice, amount) -- §5.5 Bend: depth of the strike-triggered
		// pitch drop, 0..1. see the SynthDef's bendEnv/bendRatio for the shape.
		this.addCommand("voice_bend", "if", { |msg|
			var v = msg[1].asInteger;
			if (v >= 0 and: { v < nVoices }) { voiceSynths[v].set(\bendAmt, msg[2]) };
		});

		this.addCommand("voice_drive", "if", { |msg|
			var v = msg[1].asInteger;
			if (v >= 0 and: { v < nVoices }) { voiceSynths[v].set(\drive, msg[2]) };
		});

		this.addCommand("voice_amp", "if", { |msg|
			var v = msg[1].asInteger;
			if (v >= 0 and: { v < nVoices }) { voiceSynths[v].set(\amp, msg[2]) };
		});

		this.addCommand("voice_modes", "ii", { |msg|
			var v = msg[1].asInteger;
			if (v >= 0 and: { v < nVoices }) { voiceSynths[v].set(\modes, msg[2]) };
		});

		// voice_mod(voice, balance) -- the collapsed point's Balance knob:
		// what a stream landing there does. 0 injects it into the
		// resonator, 1 bends the body with it. discrete choke (a pulse
		// here) is gone with the socket that used to carry it.
		this.addCommand("voice_mod", "if", { |msg|
			var v = msg[1].asInteger;
			if (v >= 0 and: { v < nVoices }) { voiceSynths[v].set(\modBalance, msg[2]) };
		});

		// voice_fm(voice, ratio, depth) -- FM addendum, engine-level: ratio
		// is the modulator's ratio to the voice's own fundamental, depth is
		// 0..~2 modulation index. depth=0 (the default) is a no-op.
		this.addCommand("voice_fm", "iff", { |msg|
			var v = msg[1].asInteger;
			if (v >= 0 and: { v < nVoices }) {
				voiceSynths[v].set(\fmRatio, msg[2], \fmDepth, msg[3]);
			};
		});

		// voice_noise_tune/voice_noise_q(voice, v) -- the tuneable-pink-noise
		// half of the same addendum: noiseTune is bipolar octaves on top of
		// hardness's own burst-brightness mapping, exciteQ is the burst
		// bandpass's resonance.
		this.addCommand("voice_noise_tune", "if", { |msg|
			var v = msg[1].asInteger;
			if (v >= 0 and: { v < nVoices }) { voiceSynths[v].set(\noiseTune, msg[2]) };
		});

		this.addCommand("voice_noise_q", "if", { |msg|
			var v = msg[1].asInteger;
			if (v >= 0 and: { v < nVoices }) { voiceSynths[v].set(\exciteQ, msg[2]) };
		});

		// §2.7b percussion cells' commands -- the same shape as the voice_*
		// ones above, six knobs instead of eight and no separate glide/drift/
		// choke/mod/tap/FM machinery: a G cell has no sockets to be pitched
		// by a field, chosen by a stream, or tapped by another cable.

		// g_strike(index, force) -- the cell's own trigger; there is no
		// separate T socket to send this through.
		this.addCommand("g_strike", "if", { |msg|
			var i = msg[1].asInteger;
			if (i >= 0 and: { i < nG }) { gSynths[i].set(\force, msg[2], \t_trig, 1) };
		});

		this.addCommand("g_pitch", "if", { |msg|
			var i = msg[1].asInteger;
			if (i >= 0 and: { i < nG }) { gSynths[i].set(\freq, msg[2]) };
		});

		this.addCommand("g_decay", "if", { |msg|
			var i = msg[1].asInteger;
			if (i >= 0 and: { i < nG }) { gSynths[i].set(\decay, msg[2].clip(0.01, 8)) };
		});

		this.addCommand("g_tone", "if", { |msg|
			var i = msg[1].asInteger;
			if (i >= 0 and: { i < nG }) { gSynths[i].set(\tone, msg[2]) };
		});

		this.addCommand("g_punch", "if", { |msg|
			var i = msg[1].asInteger;
			if (i >= 0 and: { i < nG }) { gSynths[i].set(\punch, msg[2]) };
		});

		this.addCommand("g_drive", "if", { |msg|
			var i = msg[1].asInteger;
			if (i >= 0 and: { i < nG }) { gSynths[i].set(\drive, msg[2]) };
		});

		this.addCommand("g_amp", "if", { |msg|
			var i = msg[1].asInteger;
			if (i >= 0 and: { i < nG }) { gSynths[i].set(\amp, msg[2]) };
		});

		// exciter_on/off(index) -- §2.4 lazy allocation: an E cell only runs
		// while it has at least one cable, rather than being an always-on
		// noise source burning CPU for nothing.
		this.addCommand("exciter_on", "i", { |msg|
			var i = msg[1].asInteger;
			if (i >= 0 and: { i < nExc } and: { excSynths[i].isNil }) {
				excSynths[i] = Synth.new(excDefs[i], [
					\out, patchBus.index + excBase + i,
					\colourModIn, patchBus.index + colourModBase + i
				], gSrc);
			};
		});

		this.addCommand("exciter_off", "i", { |msg|
			var i = msg[1].asInteger;
			if (i >= 0 and: { i < nExc } and: { excSynths[i].notNil }) {
				excSynths[i].free;
				excSynths[i] = nil;
			};
		});

		// exciter_colour(index, v) -- Colour, E2 on an S cell (§4.2).
		this.addCommand("exciter_colour", "if", { |msg|
			var i = msg[1].asInteger;
			if (i >= 0 and: { i < nExc } and: { excSynths[i].notNil }) {
				excSynths[i].set(\colour, msg[2]);
			};
		});

		// exciter_decay(index, scale) -- the other half of §4.2's E3: a plain
		// multiplier on this exciter's grain envelope and on whatever tail
		// its own recipe has. see the gateMul comment above.
		this.addCommand("exciter_decay", "if", { |msg|
			var i = msg[1].asInteger;
			if (i >= 0 and: { i < nExc } and: { excSynths[i].notNil }) {
				excSynths[i].set(\decay, msg[2].clip(0.05, 20));
			};
		});

		// exciter_gated(index, flag) -- does this S cell have >=1 incoming
		// pulse cable right now? flips it between free-running and
		// grain-on-pulse.
		this.addCommand("exciter_gated", "ii", { |msg|
			var i = msg[1].asInteger;
			if (i >= 0 and: { i < nExc } and: { excSynths[i].notNil }) {
				excSynths[i].set(\gated, msg[2]);
			};
		});

		// exciter_gate(index, dur, amp) -- fires one grain; see gateMul above.
		this.addCommand("exciter_gate", "iff", { |msg|
			var i = msg[1].asInteger;
			if (i >= 0 and: { i < nExc } and: { excSynths[i].notNil }) {
				excSynths[i].set(\gateDur, msg[2], \gateAmp, msg[3], \t_gate, 1);
			};
		});

		// exciter_fm(index, ratio, depth) -- same FM addendum as voice_fm,
		// for the S cells. no-op (depth=0) until an exciter is on, same as
		// every other per-exciter set command.
		this.addCommand("exciter_fm", "iff", { |msg|
			var i = msg[1].asInteger;
			if (i >= 0 and: { i < nExc } and: { excSynths[i].notNil }) {
				excSynths[i].set(\fmRatio, msg[2], \fmDepth, msg[3]);
			};
		});

		// patch_add(id, kind, src, dst, gain) -- id is the Lua-side cable
		// (or cable-direction) id; src/dst are absolute patchBus numbers.
		// re-adding an id that's already live frees the old synth first, so
		// this also serves as an update-in-place for anything but gain.
		this.addCommand("patch_add", "isiif", { |msg|
			var id = msg[1].asInteger;
			var kind = msg[2].asString;
			var src = msg[3].asInteger;
			var dst = msg[4].asInteger;
			var gain = msg[5];
			var defName = if (kind == "ak") { \wl_patch_ak } { \wl_patch_aa };
			if (patchSynths[id].notNil) { patchSynths[id].free };
			patchSynths[id] = Synth.new(defName, [
				\src, patchBus.index + src, \dst, patchBus.index + dst, \gain, gain
			], gPatch);
		});

		this.addCommand("patch_gain", "if", { |msg|
			var id = msg[1].asInteger;
			if (patchSynths[id].notNil) { patchSynths[id].set(\gain, msg[2]) };
		});

		this.addCommand("patch_free", "i", { |msg|
			var id = msg[1].asInteger;
			if (patchSynths[id].notNil) {
				patchSynths[id].free;
				patchSynths[id] = nil;
			};
		});

		// heart_conductance(index, v) -- §2.5 conductance, E2 on an H cell.
		// sets that node's hop delay and loss; heartwood.lua applies the same
		// mapping to the discrete side.
		this.addCommand("heart_conductance", "if", { |msg|
			var i = msg[1].asInteger;
			if (i >= 0 and: { i < nH }) {
				heartSynth.set(("c" ++ i).asSymbol, msg[2]);
			};
		});

		// not in §8's command list, but E3-with-nothing-held is spec'd as
		// master level (§4.1) and needs somewhere to land.
		this.addCommand("master_level", "f", { |msg|
			fxSynth.set(\level, msg[1]);
		});

		// rain_load(path) -- §4.1: the always-on Rain.wav ambience. Lua sends
		// its absolute path once, at init; Buffer.read is async, so \wl_rain
		// is only started once the read's completion action fires. before
		// that (and if the read never arrives -- the offline sc_check has no
		// Lua side to call this at all) rainBus just stays silent, which is
		// indistinguishable from rain_volume/rain_excite both being 0.
		this.addCommand("rain_load", "s", { |msg|
			var path = msg[1].asString;
			if (rainBuf.notNil) { rainBuf.free };
			rainBuf = Buffer.read(server, path, action: { |buf|
				if (rainSynth.notNil) { rainSynth.free };
				rainSynth = Synth.new(\wl_rain, [
					\out, rainBus.index, \bufnum, buf.bufnum
				], gSrc);
			});
		});

		// rain_volume(v) -- the rain ambience's own dry level in the mix.
		this.addCommand("rain_volume", "f", { |msg|
			fxSynth.set(\rainVol, msg[1]);
		});

		// rain_excite(v) -- how much the same rain audio excites every
		// voice's resonator, continuously, whether or not anything is patched.
		this.addCommand("rain_excite", "f", { |msg|
			voiceSynths.do({ |s| if (s.notNil) { s.set(\rainExcite, msg[1]) } });
		});
	}

	free {
		voiceSynths.do({ |s| if (s.notNil) { s.free } });
		gSynths.do({ |s| if (s.notNil) { s.free } });
		excSynths.do({ |s| if (s.notNil) { s.free } });
		patchSynths.do({ |s| if (s.notNil) { s.free } });
		if (heartSynth.notNil) { heartSynth.free };
		if (fxSynth.notNil) { fxSynth.free };
		if (excMeterSynth.notNil) { excMeterSynth.free };
		if (rainSynth.notNil) { rainSynth.free };
		if (rainBuf.notNil) { rainBuf.free };
		patchBus.free;
		excMeterBus.free;
		rainBus.free;
		gFx.free;
		gTap.free;
		gVoice.free;
		gPatch.free;
		gSrc.free;
	}
}
