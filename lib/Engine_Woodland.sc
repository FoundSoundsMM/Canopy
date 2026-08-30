// Engine_Woodland
// six modal/pinged-filter voices, DynKlank-style but hand-built so strike
// position and structure can be re-shaped live. see docs/woodland-spec.md
// §8 for the woodiness recipe and §9 for build phase 2's scope: the six
// voices + strike, driven by one D cell (Knocker) from Lua. no exciters,
// heartwood, or patch matrix yet — those are later phases.

Engine_Woodland : CroneEngine {
	var gSrc, gPatch, gVoice, gTap, gFx;
	var voiceBus;
	var voiceSynths;
	var fxSynth;

	// name, freq, structureBase (0..1, ignored when oddOnly=1), oddOnly, dampBase, decay
	// §8 "per-voice defaults" table.
	classvar voiceDefs = #(
		#(\oak,   65,  0.55, 0, 1.1, 2.4),
		#(\rowan, 330, 0.75, 0, 0.6, 1.8),
		#(\ash,   146, 0.5,  1, 0.8, 1.2),
		#(\hazel, 220, 0.95, 0, 1.3, 0.35),
		#(\yew,   49,  0.35, 0, 0.4, 6.0),
		#(\alder, 98,  0.6,  0, 0.9, 2.0)
	);

	*new { arg context, doneCallback;
		^super.new(context, doneCallback);
	}

	alloc {
		var server = context.server;

		gSrc = Group.new(context.xg);
		gPatch = Group.after(gSrc);
		gVoice = Group.after(gPatch);
		gTap = Group.after(gVoice);
		gFx = Group.after(gTap);

		// one mono bus per voice (§7.3 "6 voice outputs")
		voiceBus = Bus.audio(server, 6);

		SynthDef(\woodland_voice, {
			arg out=0, t_trig=0, force=0.6, hardness=0.5, position=0.15,
				freq=110, damp=0.8, bright=0.5, drive=0.2, structure=0.5,
				oddOnly=0, decayBase=2.0, amp=1.0, modes=6;

			var harmonicRatio = [1, 2, 3, 4, 5, 6];
			var barRatio = [1, 2.756, 5.404, 8.933, 13.34, 18.64];

			// §8.3: a noise-burst exciter, never a raw impulse. hard mallet
			// (hardness -> 1) = brighter, shorter burst.
			var burstDur = 0.008 - (hardness.clip(0, 1) * 0.006);
			var bpFreq = 800 + (hardness.clip(0, 1) * 5200);
			var env = EnvGen.kr(Env.perc(0.0003, burstDur), t_trig);
			var exc = BPF.ar(WhiteNoise.ar(1), bpFreq, 0.35) * env * force;

			// §8.5: amplitude-dependent pitch drop -- the "thunk" of a hard hit.
			var pitchDrop = 1 - (force.clip(0, 1) * 0.02);

			var modeSig = Mix.fill(6, { |i|
				var n = i + 1;
				// §8.1: morph harmonic -> free-free bar via `structure`;
				// Ash overrides with an odd-only ratio set ("hollow tube").
				var ratio = Select.kr(oddOnly, [
					harmonicRatio[i] + ((barRatio[i] - harmonicRatio[i]) * structure),
					(2 * n) - 1
				]);
				var mfreq = freq * ratio * pitchDrop;
				// §8.2: frequency-dependent damping -- high modes die fast.
				var mdecay = (decayBase * (ratio ** damp.neg)).clip(0.02, 20);
				// §8.4: strike position comb-notches modes with a node there.
				var mamp = (pi * position * n).sin;
				var active = i < modes;
				Ringz.ar(exc, mfreq, mdecay) * mamp * active;
			});

			// body cavity + §8.5 gentle nonlinearity + the safety net every
			// voice bus needs once feedback patching exists (§6 notes) --
			// cheap to add now, load-bearing later.
			var body = AllpassC.ar(modeSig, 0.05, [0.0207, 0.0313], 0.2);
			var driven = (body * (1 + (drive * 3))).tanh;
			var toned = LPF.ar(driven, 400 + (bright.clip(0, 1) * 9000));
			var sig = Limiter.ar(LeakDC.ar(toned), 0.95) * amp * 0.35;

			Out.ar(out, sig);
		}).add;

		SynthDef(\woodland_fx, {
			arg busIn=0, out=0, size=0.5, damp=0.5, mix=0.3, level=0.8;
			var dry = In.ar(busIn, 6).sum;
			var wet = FreeVerb.ar(dry, mix, size, damp);
			Out.ar(out, (wet * level) ! 2);
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
				\decayBase, def[5]
			], gVoice);
		});

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
		if (fxSynth.notNil) { fxSynth.free };
		voiceBus.free;
		gFx.free;
		gTap.free;
		gVoice.free;
		gPatch.free;
		gSrc.free;
	}
}
