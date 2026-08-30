// Engine_Woodland
// six modal/pinged-filter voices, DynKlank-style but hand-built so strike
// position and structure can be re-shaped live. see docs/woodland-spec.md
// §8 for the woodiness recipe, §9 for the build order.
//
// build phase 4 adds the ten S-cell exciters (§2.4), the generic audio-rate
// patch matrix (§7.3's \patch_aa / \patch_ak), and the Sap/Sway/Moss stream
// inputs on the voice synth. heartwood and voice<->voice feedback are still
// ahead.

Engine_Woodland : CroneEngine {
	var gSrc, gPatch, gVoice, gTap, gFx;
	var voiceBus, patchBus;
	var voiceSynths;
	var excSynths;
	var patchSynths;
	var fxSynth;

	// name, freq, structureBase (0..1, ignored when oddOnly=1), oddOnly, dampBase, decay
	// §8 "per-voice defaults" table.
	// nested arrays inside a literal array are written WITHOUT their own `#`
	// -- sclang's grammar only allows the `#` on the outermost one, and an
	// inner `#[` is a syntax error that fails the whole class library.
	classvar voiceDefs = #[
		[\oak,   65,  0.55, 0, 1.1, 2.4],
		[\rowan, 330, 0.75, 0, 0.6, 1.8],
		[\ash,   146, 0.5,  1, 0.8, 1.2],
		[\hazel, 220, 0.95, 0, 1.3, 0.35],
		[\yew,   49,  0.35, 0, 0.4, 6.0],
		[\alder, 98,  0.6,  0, 0.9, 2.0]
	];

	// §2.4 exciter table, in the same order as topology.lua's S_CELLS list --
	// index i here IS the S cell's `index` field on the Lua side. flat array,
	// no nesting, to stay clear of the bug noted above -- and `#[` on the
	// outermost bracket, because sclang's grammar only accepts a *literal*
	// on the right of a classvar `=`. a bare `[...]` here is a parse error
	// that takes the whole class library down with it.
	classvar excDefs = #[
		\wl_exc_bracken, \wl_exc_gorse, \wl_exc_ember, \wl_exc_windfall,
		\wl_exc_mistle, \wl_exc_wisp, \wl_exc_hollow, \wl_exc_drizzle,
		\wl_exc_loam, \wl_exc_beck
	];

	// offsets into the single `patchBus` block (§7.3's "10 exciter outputs /
	// 6 voice exciter-inputs / 24 voice modulation inputs" collapsed into one
	// allocation so the Lua side only needs to add an offset, not track five
	// bus objects). spec calls the modulation buses "control buses"; they are
	// implemented here as audio buses instead, because Out.kr *overwrites* a
	// bus each block while Out.ar *adds* to it -- and several cables landing
	// on the same node's Sway/Moss/Sap input need to sum, not fight. keep
	// these six numbers in sync with bridge.lua's `bridge.BUS` table.
	classvar excBase = 0, excInBase = 10, swayBase = 16, mossBase = 22,
		colourModBase = 28, patchTotal = 38;

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

		// one mono bus per voice (§7.3 "6 voice outputs")
		voiceBus = Bus.audio(server, 6);
		// see the classvar block above for the six sub-ranges packed in here
		patchBus = Bus.audio(server, patchTotal);

		SynthDef(\woodland_voice, {
			arg out=0, t_trig=0, force=0.6, hardness=0.5, position=0.15,
				freq=110, damp=0.8, bright=0.5, drive=0.2, structure=0.5,
				oddOnly=0, decayBase=2.0, amp=1.0, modes=6,
				t_choke=0, chokeDepth=0.9, chokeTime=0.25,
				excIn=0, swayIn=0, mossIn=0,
				sapLevel=0.6, swayBalance=0, mossCurve=0.5;

			var harmonicRatio = [1, 2, 3, 4, 5, 6];
			var barRatio = [1, 2.756, 5.404, 8.933, 13.34, 18.64];

			// §2.2 Sap: a cabled S (or, later, H) stream injected audio-rate
			// into the resonator, alongside the voice's own strike exciter.
			// §2.2 Sway: a stream bends pitch <-> structure; §2.2 Moss: a
			// stream sets damping <-> brightness. each node's own E2 char
			// (sapLevel / swayBalance / mossCurve) decides how much and,
			// for Sway/Moss, which of the two targets it leans toward.
			var extExc = In.ar(excIn, 1);
			var swayStream = In.ar(swayIn, 1);
			var mossStream = In.ar(mossIn, 1);

			var pitchBend = swayStream * swayBalance.max(0) * 0.06;
			var structBend = swayStream * swayBalance.neg.max(0) * 0.4;
			var structureEff = (structure + structBend).clip(0, 1.3);

			var dampMod = mossStream * (1 - mossCurve) * 0.6;
			var brightMod = mossStream * mossCurve * 0.6;

			// §8.3: a noise-burst exciter, never a raw impulse. hard mallet
			// (hardness -> 1) = brighter, shorter burst.
			var burstDur = 0.008 - (hardness.clip(0, 1) * 0.006);
			var bpFreq = 800 + (hardness.clip(0, 1) * 5200);
			// .ar, not .kr: burstDur is 2-8 ms and a control period is ~1.3 ms
			// at norns' block size, so a kr envelope quantises the whole burst
			// to one or two steps and `hardness` stops shortening it at all.
			var env = EnvGen.ar(Env.perc(0.0003, burstDur), t_trig);
			var exc = BPF.ar(WhiteNoise.ar(1), bpFreq, 0.35) * env * force;
			var totalExc = exc + (extExc * sapLevel);

			// §8.5: amplitude-dependent pitch drop -- the "thunk" of a hard hit.
			var pitchDrop = 1 - (force.clip(0, 1) * 0.02);

			var modeSig = Mix.fill(6, { |i|
				var n = i + 1;
				// §8.1: morph harmonic -> free-free bar via `structure`;
				// Ash overrides with an odd-only ratio set ("hollow tube").
				var ratio = Select.kr(oddOnly, [
					harmonicRatio[i] + ((barRatio[i] - harmonicRatio[i]) * structureEff),
					(2 * n) - 1
				]);
				var mfreq = freq * ratio * pitchDrop * (1 + pitchBend);
				// §8.2: frequency-dependent damping -- high modes die fast.
				var mdecay = (decayBase * (ratio ** (damp + dampMod).neg)).clip(0.02, 20);
				// §8.4: strike position comb-notches modes with a node there.
				var mamp = (pi * position * n).sin;
				var active = i < modes;
				Ringz.ar(totalExc, mfreq, mdecay) * mamp * active;
			});

			// body cavity + §8.5 gentle nonlinearity + the safety net every
			// voice bus needs once feedback patching exists (§6 notes) --
			// cheap to add now, load-bearing later. two cascaded (not
			// parallel-array) allpass stages, so this stays strictly mono --
			// an array delaytime here would multichannel-expand to stereo
			// and bleed this voice's second channel into the next voice's
			// bus slot.
			var body = AllpassC.ar(AllpassC.ar(modeSig, 0.05, 0.0207, 0.2), 0.05, 0.0313, 0.2);
			var driven = (body * (1 + (drive * 3))).tanh;
			var toned = LPF.ar(driven, 400 + ((bright + brightMod).clip(0, 1) * 9000));

			// §2.2 Moss: "a pulse chokes it". a hand on the bar -- duck fast,
			// let it back in over chokeTime. \exp needs a non-zero floor, and
			// clipping chokeDepth guarantees one whatever Lua sends.
			var chokeFloor = 1 - (chokeDepth.clip(0, 1) * 0.98);
			var choke = EnvGen.kr(
				Env([1, chokeFloor, 1], [0.006, chokeTime.clip(0.01, 4)], \exp),
				t_choke);

			var sig = Limiter.ar(LeakDC.ar(toned), 0.95) * amp * 0.35 * choke;

			Out.ar(out, sig);
		}).add;

		SynthDef(\woodland_fx, {
			arg busIn=0, out=0, size=0.5, damp=0.5, mix=0.3, level=0.8;
			var dry = In.ar(busIn, 6).sum;
			var wet = FreeVerb.ar(dry, mix, size, damp);
			Out.ar(out, (wet * level) ! 2);
		}).add;

		// shared gate envelope for every exciter (§2.4: "an S cell is
		// continuous until a pulse is cabled into it. a D->S cable turns the
		// exciter into an enveloped grain, fired by that pulse"). `gated`
		// flips that switch; `t_gate` fires one grain while gated.
		gateMul = { |tGate, gated, dur, amp|
			var env = EnvGen.ar(Env.perc(0.002, dur.clip(0.02, 4)), tGate) * amp;
			Select.ar(gated, [DC.ar(1), env]);
		};

		// §2.4 exciter recipes. each is deliberately its own thing -- these
		// are noise colours and textures, not one macro. `colour` (E2, §4.2)
		// is the one thing that matters about each; the exact curve is a
		// sound-design call, tune by ear once this is on hardware. `c` folds
		// in `colourModIn`, the other half of "S<->S: each modulates the
		// other's colour" (§6) -- the "and level" half of that sentence is
		// not implemented; two S cells only cross-modulate colour for now.
		//
		// InFeedback, not In: the colour-mod buses are written by \wl_patch_ak
		// synths in gPatch, which runs AFTER gSrc, and In.ar returns silence
		// for a bus nothing has touched yet this cycle. S<->S is a genuine
		// feedback path round the node order, so it has to read last cycle's
		// block -- with plain In.ar the cross-modulation is a permanent no-op.

		SynthDef(\wl_exc_bracken, { arg out=0, colour=0.5, colourModIn=0,
				gated=0, t_gate=0, gateDur=0.15, gateAmp=0.8;
			var c = (colour + InFeedback.ar(colourModIn, 1)).clip(0, 1);
			var bp = BPF.ar(WhiteNoise.ar(1), 500 + (c * 4000), 0.5);
			var crackle = Decay2.ar(Dust.ar(15 + (c * 45)), 0.001, 0.02) * WhiteNoise.ar(1);
			var sig = (bp * 0.6) + (crackle * 0.5);
			Out.ar(out, sig * gateMul.value(t_gate, gated, gateDur, gateAmp) * 0.3);
		}).add;

		SynthDef(\wl_exc_gorse, { arg out=0, colour=0.5, colourModIn=0,
				gated=0, t_gate=0, gateDur=0.15, gateAmp=0.8;
			var c = (colour + InFeedback.ar(colourModIn, 1)).clip(0, 1);
			var sig = BPF.ar(WhiteNoise.ar(1), 3500 + (c * 5000), 0.06);
			Out.ar(out, sig * gateMul.value(t_gate, gated, gateDur, gateAmp) * 0.3);
		}).add;

		SynthDef(\wl_exc_ember, { arg out=0, colour=0.5, colourModIn=0,
				gated=0, t_gate=0, gateDur=0.15, gateAmp=0.8;
			var c = (colour + InFeedback.ar(colourModIn, 1)).clip(0, 1);
			var trig = Dust.ar(4 + (c * 40));
			var sig = Decay2.ar(trig, 0.0005, 0.03 + (c * 0.05)) * WhiteNoise.ar(1);
			Out.ar(out, sig * gateMul.value(t_gate, gated, gateDur, gateAmp) * 0.3);
		}).add;

		SynthDef(\wl_exc_windfall, { arg out=0, colour=0.5, colourModIn=0,
				gated=0, t_gate=0, gateDur=0.15, gateAmp=0.8;
			var c = (colour + InFeedback.ar(colourModIn, 1)).clip(0, 1);
			var trig = Dust.ar(2 + (c * 10));
			var genv = EnvGen.ar(Env.perc(0.001, 0.04 + (c * 0.08)), trig);
			var sig = BPF.ar(WhiteNoise.ar(1), 900 + (c * 3000), 0.3) * genv * 2;
			Out.ar(out, sig * gateMul.value(t_gate, gated, gateDur, gateAmp) * 0.3);
		}).add;

		SynthDef(\wl_exc_mistle, { arg out=0, colour=0.5, colourModIn=0,
				gated=0, t_gate=0, gateDur=0.15, gateAmp=0.8;
			var c = (colour + InFeedback.ar(colourModIn, 1)).clip(0, 1);
			var trig = Dust.ar(1 + (c * 4));
			var fenv = EnvGen.ar(Env([1800 + (c * 1500), 3200 + (c * 2000), 2200], [0.02, 0.06], \exp), trig);
			var aenv = EnvGen.ar(Env.perc(0.005, 0.09), trig);
			var sig = SinOsc.ar(fenv) * aenv;
			Out.ar(out, sig * gateMul.value(t_gate, gated, gateDur, gateAmp) * 0.3);
		}).add;

		// control-rate by spec ("slow wandering random walk, control-rate");
		// K2A.ar upsamples it onto the shared audio-rate exciter bus so it
		// can sum and gate the same way as the other nine.
		SynthDef(\wl_exc_wisp, { arg out=0, colour=0.5, colourModIn=0,
				gated=0, t_gate=0, gateDur=0.15, gateAmp=0.8;
			var c = (colour + InFeedback.ar(colourModIn, 1)).clip(0, 1);
			var sig = K2A.ar(LFNoise1.kr(0.3 + (c * 2)).range(-1, 1));
			Out.ar(out, sig * gateMul.value(t_gate, gated, gateDur, gateAmp) * 0.3);
		}).add;

		SynthDef(\wl_exc_hollow, { arg out=0, colour=0.5, colourModIn=0,
				gated=0, t_gate=0, gateDur=0.15, gateAmp=0.8;
			var c = (colour + InFeedback.ar(colourModIn, 1)).clip(0, 1);
			var sig = CombL.ar(PinkNoise.ar(1), 0.3, 0.05 + (c * 0.2), 3 + (c * 5));
			Out.ar(out, sig * gateMul.value(t_gate, gated, gateDur, gateAmp) * 0.3);
		}).add;

		SynthDef(\wl_exc_drizzle, { arg out=0, colour=0.5, colourModIn=0,
				gated=0, t_gate=0, gateDur=0.15, gateAmp=0.8;
			var c = (colour + InFeedback.ar(colourModIn, 1)).clip(0, 1);
			var trig = Dust.ar(1 + (c * 8));
			var tail = Decay2.ar(trig, 0.001, 0.15 + (c * 0.3)) * PinkNoise.ar(1);
			var sig = BPF.ar(tail, 2000, 0.6) * 3;
			Out.ar(out, sig * gateMul.value(t_gate, gated, gateDur, gateAmp) * 0.3);
		}).add;

		SynthDef(\wl_exc_loam, { arg out=0, colour=0.5, colourModIn=0,
				gated=0, t_gate=0, gateDur=0.15, gateAmp=0.8;
			var c = (colour + InFeedback.ar(colourModIn, 1)).clip(0, 1);
			var sig = LPF.ar(BrownNoise.ar(1), 80 + (c * 500));
			Out.ar(out, sig * gateMul.value(t_gate, gated, gateDur, gateAmp) * 0.3);
		}).add;

		SynthDef(\wl_exc_beck, { arg out=0, colour=0.5, colourModIn=0,
				gated=0, t_gate=0, gateDur=0.15, gateAmp=0.8;
			var c = (colour + InFeedback.ar(colourModIn, 1)).clip(0, 1);
			var cutoff = SinOsc.kr(0.1 + (c * 0.4)).range(300, 1200 + (c * 1500));
			var sig = RLPF.ar(PinkNoise.ar(1), cutoff, 0.25);
			Out.ar(out, sig * gateMul.value(t_gate, gated, gateDur, gateAmp) * 0.3);
		}).add;

		// §7.3's generic audio-rate patch matrix. one synth per live cable
		// that means something continuous (§6): S -> Sap/Sway/Moss is a
		// straight pass (\wl_patch_aa); S <-> S colour cross-mod follows the
		// source's amplitude first (\wl_patch_ak). `src`/`dst` are absolute
		// bus numbers computed on the Lua side (bridge.BUS) and fixed at
		// creation, like `out` on the voice/exciter synths.
		SynthDef(\wl_patch_aa, { arg src=0, dst=0, gain=0.6;
			Out.ar(dst, In.ar(src, 1) * gain);
		}).add;

		SynthDef(\wl_patch_ak, { arg src=0, dst=0, gain=0.6;
			Out.ar(dst, LPF.ar(Amplitude.ar(In.ar(src, 1), 0.01, 0.1), 20) * gain);
		}).add;

		server.sync;

		voiceSynths = Array.newClear(6);
		voiceDefs.do({ |def, i|
			voiceSynths[i] = Synth.new(\woodland_voice, [
				\out, voiceBus.index + i,
				\freq, def[1],
				\structure, def[2],
				\oddOnly, def[3],
				\damp, def[4],
				\decayBase, def[5],
				\excIn, patchBus.index + excInBase + i,
				\swayIn, patchBus.index + swayBase + i,
				\mossIn, patchBus.index + mossBase + i
			], gVoice);
		});

		excSynths = Array.newClear(10);
		patchSynths = Dictionary.new;

		fxSynth = Synth.new(\woodland_fx, [
			\busIn, voiceBus.index,
			\out, context.out_b.index
		], gFx);

		// strike(voice, force, hardness, position)
		this.addCommand("strike", "ifff", { |msg|
			var v = msg[1].asInteger;
			if (v >= 0 and: { v < 6 }) {
				voiceSynths[v].set(
					\force, msg[2], \hardness, msg[3], \position, msg[4], \t_trig, 1
				);
			};
		});

		this.addCommand("voice_pitch", "if", { |msg|
			var v = msg[1].asInteger;
			if (v >= 0 and: { v < 6 }) { voiceSynths[v].set(\freq, msg[2]) };
		});

		// grain (§8: "reachable from Grain as a macro plus individually from
		// PARAMS") morphs structure/damp/bright/drive together around each
		// voice's baked-in baseline. the exact curve is a sound-design call,
		// not a spec requirement -- tune by ear once this is on hardware.
		this.addCommand("voice_grain", "if", { |msg|
			var v = msg[1].asInteger;
			var g = msg[2].clip(0, 1);
			if (v >= 0 and: { v < 6 }) {
				var sBase = voiceDefs[v][2];
				var dBase = voiceDefs[v][4];
				var structure = (sBase - 0.25 + (g * 0.5)).clip(0, 1.3);
				var damp = (dBase + ((0.5 - g) * 0.4)).clip(0.2, 1.6);
				var bright = (0.15 + (g * 0.75)).clip(0, 1);
				var drive = g;
				voiceSynths[v].set(
					\structure, structure, \damp, damp, \bright, bright, \drive, drive
				);
			};
		});

		this.addCommand("voice_damp", "if", { |msg|
			var v = msg[1].asInteger;
			if (v >= 0 and: { v < 6 }) { voiceSynths[v].set(\damp, msg[2]) };
		});

		this.addCommand("voice_bright", "if", { |msg|
			var v = msg[1].asInteger;
			if (v >= 0 and: { v < 6 }) { voiceSynths[v].set(\bright, msg[2]) };
		});

		this.addCommand("voice_pos", "if", { |msg|
			var v = msg[1].asInteger;
			if (v >= 0 and: { v < 6 }) { voiceSynths[v].set(\position, msg[2]) };
		});

		this.addCommand("voice_drive", "if", { |msg|
			var v = msg[1].asInteger;
			if (v >= 0 and: { v < 6 }) { voiceSynths[v].set(\drive, msg[2]) };
		});

		this.addCommand("voice_amp", "if", { |msg|
			var v = msg[1].asInteger;
			if (v >= 0 and: { v < 6 }) { voiceSynths[v].set(\amp, msg[2]) };
		});

		this.addCommand("voice_modes", "ii", { |msg|
			var v = msg[1].asInteger;
			if (v >= 0 and: { v < 6 }) { voiceSynths[v].set(\modes, msg[2]) };
		});

		// voice_choke(voice, depth, time) -- see §2.2 Moss.
		this.addCommand("voice_choke", "iff", { |msg|
			var v = msg[1].asInteger;
			if (v >= 0 and: { v < 6 }) {
				voiceSynths[v].set(
					\chokeDepth, msg[2], \chokeTime, msg[3], \t_choke, 1
				);
			};
		});

		// voice_sap/sway/moss(voice, v) -- each node's own E2 character
		// (§4.2: Sap's injection filter, Sway's bend depth/balance, Moss's
		// damping curve) forwarded from the stream-modulation half of §2.2,
		// separate from the pulse-choke path voice_choke already covers.
		this.addCommand("voice_sap", "if", { |msg|
			var v = msg[1].asInteger;
			if (v >= 0 and: { v < 6 }) { voiceSynths[v].set(\sapLevel, msg[2]) };
		});

		this.addCommand("voice_sway", "if", { |msg|
			var v = msg[1].asInteger;
			if (v >= 0 and: { v < 6 }) { voiceSynths[v].set(\swayBalance, msg[2]) };
		});

		this.addCommand("voice_moss", "if", { |msg|
			var v = msg[1].asInteger;
			if (v >= 0 and: { v < 6 }) { voiceSynths[v].set(\mossCurve, msg[2]) };
		});

		// exciter_on/off(index) -- §2.4 lazy allocation: an S cell only runs
		// while it has at least one cable.
		this.addCommand("exciter_on", "i", { |msg|
			var i = msg[1].asInteger;
			if (i >= 0 and: { i < 10 } and: { excSynths[i].isNil }) {
				excSynths[i] = Synth.new(excDefs[i], [
					\out, patchBus.index + excBase + i,
					\colourModIn, patchBus.index + colourModBase + i
				], gSrc);
			};
		});

		this.addCommand("exciter_off", "i", { |msg|
			var i = msg[1].asInteger;
			if (i >= 0 and: { i < 10 } and: { excSynths[i].notNil }) {
				excSynths[i].free;
				excSynths[i] = nil;
			};
		});

		// exciter_colour(index, v) -- Colour, E2 on an S cell (§4.2).
		this.addCommand("exciter_colour", "if", { |msg|
			var i = msg[1].asInteger;
			if (i >= 0 and: { i < 10 } and: { excSynths[i].notNil }) {
				excSynths[i].set(\colour, msg[2]);
			};
		});

		// exciter_gated(index, flag) -- does this S cell have >=1 incoming D
		// cable right now? flips it between free-running and grain-on-pulse.
		this.addCommand("exciter_gated", "ii", { |msg|
			var i = msg[1].asInteger;
			if (i >= 0 and: { i < 10 } and: { excSynths[i].notNil }) {
				excSynths[i].set(\gated, msg[2]);
			};
		});

		// exciter_gate(index, dur, amp) -- fires one grain; see gateMul above.
		this.addCommand("exciter_gate", "iff", { |msg|
			var i = msg[1].asInteger;
			if (i >= 0 and: { i < 10 } and: { excSynths[i].notNil }) {
				excSynths[i].set(\gateDur, msg[2], \gateAmp, msg[3], \t_gate, 1);
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

		this.addCommand("canopy", "fff", { |msg|
			fxSynth.set(\size, msg[1], \damp, msg[2], \mix, msg[3]);
		});

		// not in §8's command list, but E3-with-nothing-held is spec'd as
		// master level (§4.1) and needs somewhere to land.
		this.addCommand("master_level", "f", { |msg|
			fxSynth.set(\level, msg[1]);
		});
	}

	free {
		voiceSynths.do({ |s| if (s.notNil) { s.free } });
		excSynths.do({ |s| if (s.notNil) { s.free } });
		patchSynths.do({ |s| if (s.notNil) { s.free } });
		if (fxSynth.notNil) { fxSynth.free };
		voiceBus.free;
		patchBus.free;
		gFx.free;
		gTap.free;
		gVoice.free;
		gPatch.free;
		gSrc.free;
	}
}
