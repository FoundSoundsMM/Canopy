// Engine_Canopy
// four modal/pinged-filter voices, DynKlank-style but hand-built so strike
// position and structure can be re-shaped live. see docs/canopy-spec.md
// §8 for the woodiness recipe, §9 for the build order.
//
// build phase 4 added the S-cell exciters (§2.4), the generic audio-rate
// patch matrix (§7.3's \patch_aa / \patch_ak), and the stream inputs on the
// voice synth. build phase 5 added the continuous half of the
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
// the output Compressor are both gone.
//
// the four field recordings (rain, cicada, thunder, sea) used to run as
// always-on loops with a fader each. they are four playable cells now
// (\wl_smp x nSmp, §2.5): the buffer is the same, but nothing sounds until a
// pulse triggers it, and what it does then is swell in under an attack and
// out under a fall the player sets per cell. each one pans itself by where
// its cell sits and sums into ONE shared stereo bus, smpBus, which
// \woodland_fx reads -- the same arrangement the loops had, and for the same
// reason: four buses to carry one bed is three buses too many.
//
// the gusts (§2.11): the Q4/Q6 step-sequencer lanes' ten cells become ten
// (later grown to twelve)
// small drone synths (\wl_gust) -- a folded triangle core under a slow
// attack/slow decay envelope, cross-modulated by whatever is cabled in,
// loosely after a Ciat-Lonbarde Deerhorn and deliberately not a clone of
// one. they are the single exception to "nothing is heard without a cable":
// each pans itself by its cell's column into a shared bus, that bus runs
// through one global delay line (\wl_gust_space), and \woodland_fx reads the
// result alongside the Output row and the sample cells.
//
// the grid overhaul changes \woodland_fx more than anything since build
// phase 6: there is no automatic mix left at all. a voice's or percussion
// cell's own tap bus and an exciter both used to reach \woodland_fx
// directly, panned at a fixed compile-time position per source; now NONE of them do, and \woodland_fx reads only a bank of
// sixteen `outBus` channels (the Output row) that ordinary patch cables have
// to be routed into for anything to be heard at all. discrete choke (a
// pulse on the old M socket) is gone too -- every pulse strikes a voice now
// -- so \woodland_voice lost its choke envelope along with `tapLevel`'s
// separate output-level knob; loudness at each Output-row position is
// purely that cable's own gain. exciters trimmed from twenty to six.

Engine_Canopy : CroneEngine {
	var gSrc, gPatch, gVoice, gTap, gFx;
	var patchBus, excMeterBus, outLevelBus, smpBus, gustBus, gustSpaceBus;
	var voiceSynths;
	var gSynths;
	var excSynths;
	var patchSynths;
	var fxSynth;
	var excMeterSynth;
	// §2.5 the four sample cells. one buffer each, read async by smp_load;
	// one always-on \wl_smp synth each, started as soon as that buffer lands.
	// smpArgs holds every knob Lua has pushed for a slot, so a synth started
	// after the knobs have moved comes up where the player left it rather
	// than at the SynthDef's defaults.
	var smpBufs;
	var smpSynths;
	var smpArgs;
	var gustSynths;
	var gustSpaceSynth;
	var lfoSynths;

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

	classvar nVoices = 4, nExc = 6, nG = 6, nOut = 16, nSmp = 4,
		nGust = 12,
		nLfo = 4;

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
	// sixteen fixed-pan buses). `lfoOutBase` is one sine tap per LFO cell, no
	// mod-input bus of its own since the family is a pure source (see
	// bridge.lua's BUS comment). the heartwood's two bus families are gone
	// with the lattice itself; the four sample cells that took its seats mix
	// themselves on their own panned path and address no bus here.
	classvar excBase = 0, colourModBase = 6, modInBase = 12,
		voiceOutBase = 16, gvoiceOutBase = 20, outBase = 26,
		gustOutBase = 42, gustModBase = 54, lfoOutBase = 66,
		patchTotal = 70;

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
		// §4.1b the mixer's channel faders: one control-rate value per
		// Output-row cell, read by \woodland_fx. a control bus rather than
		// sixteen synth arguments because the fader has to be settable one
		// channel at a time and an array arg can only be set whole.
		outLevelBus = Bus.control(server, nOut);
		outLevelBus.setn(Array.fill(nOut, { 1.0 }));
		// §2.5 the sample cells: one stereo bus, always allocated, silent
		// until smp_load's buffers land and the \wl_smp synths start writing
		// to it. each one pans itself into this, already scaled by its own
		// Level, and \woodland_fx reads it with a plain In.ar -- both live in
		// groups after gSrc, so a block with nothing writing here is just a
		// block of zeros, not stale data.
		smpBus = Bus.audio(server, 2);
		// §2.11 the gusts. two stereo buses rather than one, because the
		// family's automatic route to the mix runs through a delay line and
		// the delay has to read the sum of all twelve before \woodland_fx sees
		// any of it: every \wl_gust pans itself into `gustBus`, \wl_gust_space
		// reads that and writes dry-plus-delayed into `gustSpaceBus`, and
		// \woodland_fx reads only the second. this is the one signal path on
		// the panel a cable is not required to complete -- everything else
		// reaches the speakers through an Output-row cell or not at all.
		gustBus = Bus.audio(server, 2);
		gustSpaceBus = Bus.audio(server, 2);

		// smpBufs/smpSynths hold one buffer and one \wl_smp synth per sample
		// cell, filled in as smp_load's async reads land; smpArgs is every
		// knob Lua has pushed for that slot, so a synth started after the
		// knobs moved comes up where the player left it rather than at the
		// SynthDef's defaults. all three have to exist as arrays before any
		// smp_* command can index into them -- without that, `smpSynths[i]`
		// and `smpArgs[i]` are both nil and the whole command is silently
		// dropped, so no cell's synth is ever created no matter what is
		// pushed at it.
		smpBufs = Array.newClear(nSmp);
		smpSynths = Array.newClear(nSmp);
		smpArgs = Array.fill(nSmp, { () });

		SynthDef(\woodland_voice, {
			arg tapOut=0, t_trig=0, force=0.6, hardness=0.5, position=0.15,
				freq=110, damp=0.8, bright=0.5, drive=0.2, structure=0.5,
				oddOnly=0, decayBase=2.0, amp=1.0, modes=6,
				modIn=0, modBalance=0.5,
				fmRatio=2.0, fmDepth=0, noiseTune=0, exciteQ=0.35,
				glide=0.02, driftDepth=0.06, driftRate=0.07, driftSeed=0,
				bendAmt=0;

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
			// a voice is excited by its own strike burst and by whatever a
			// cable puts on its mod path, and by nothing else -- the old
			// rain_excite path, which fed a field recording continuously into
			// every resonator, is gone.
			var totalExc = exc + (inject * 0.8);

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

		// §2.11 a gust: one of the twelve small drone synths on the bottom two
		// rows. loosely a Ciat-Lonbarde Deerhorn voice and deliberately not a
		// clone of one -- a triangle core, folded rather than filtered into
		// shape, under a slow attack/slow decay envelope, cross-modulated by
		// whatever is cabled in.
		//
		// unlike every other source here it writes to TWO places: its own
		// mono tap (`out`, the gustOutBase range -- what a cable out of the
		// cell carries), and a panned copy into the shared `spaceOut` stereo
		// bus, which is the automatic route to the mix that makes a gust
		// audible with nothing patched at all. `pan` is fixed by the cell's
		// column on the Lua side and pushed once at init.
		//
		// InFeedback on the mod bus, not In: this lives in gVoice, which runs
		// after gPatch, but a gust cabled to another gust is a cycle -- there
		// is no node order that resolves it, so one block of latency is the
		// answer, exactly as it is for \wl_patch_aa.
		SynthDef(\wl_gust, {
			arg out=0, spaceOut=0, modIn=0, t_trig=0, force=0.8,
				freq=220, atk=0.8, dcy=3.0, timbre=0.35, cross=0.3,
				amp=0.7, pan=0;

			var x = cross.clip(0, 1);
			var modRaw = InFeedback.ar(modIn, 1);
			// MOD_MAKEUP: what a gust's own tap actually carries, undone.
			// this is the whole reason Cross did nothing audible before.
			// \wl_gust writes its tap at `env * amp * 0.3` -- so a gust at
			// its default Level of 0.7, sounding at full envelope, puts about
			// 0.2 peak on the bus. straight into the fmSemis line below that
			// is a fifth of a semitone at maximum Cross: a slight waver, not
			// modulation. the tap level is right for a mix and wrong for a
			// modulator, so it is scaled back up to something near unity here
			// rather than made hotter at the source, where it would change
			// what every cable OUT of a gust sounds like.
			//
			// soft-limited after that, and only then: a cross-mod loop
			// between two gusts is a legal patch, and the tanh is what stops
			// it from being a runaway one. the mod signal is deliberately
			// kept bipolar (no rectification) so a negative-gain cable pulls
			// the pitch the other way, the same as everywhere else on the
			// panel.
			var mod = (modRaw * 5).tanh * x;

			// the two things a cable does to a gust, and the reason cabling
			// two of them together reads as cross-modulation rather than as
			// a mix: it bends the pitch, and it opens the fold (below), so a
			// modulating gust is heard in this one's timbre as well as in its
			// tuning.
			//
			// two octaves either way at full Cross, through .midiratio so the
			// bend stays musical rather than linear. this was a fifth, which
			// at audio rate is a chorus and not an FM index -- at two octaves
			// a pair of gusts cabled together and both turned up genuinely
			// modulate each other, which is what Cross was always for.
			var fmSemis = mod * 24;
			// the tuned pitch, lagged so an OSC retune is a move rather than
			// a step, and then the modulated one on top of it. the two are
			// kept apart because only the oscillators want the modulated
			// version -- see the filter below.
			var fBase = Lag.kr(freq, 0.04);
			var f = (fBase * fmSemis.midiratio).clip(8, 8000);

			// a slow swell and a slow fall. the curves matter more than the
			// times do: \sin-ish rise (curve 3) is the shape of something
			// arriving rather than a ramp, and the -4 fall keeps a long
			// decay from sitting at half volume for most of its length.
			//
			// Lag on the envelope, not on the output: re-pressing a key
			// part-way up a swell restarts Env.perc from zero, and a 5 ms
			// lag turns the discontinuity that would be into a lift. it is
			// short enough not to soften the attack itself, which is seconds
			// long by design.
			var env = Lag.ar(
				EnvGen.ar(Env.perc(atk.clip(0.01, 12), dcy.clip(0.05, 30), 1, [3, -4]), t_trig),
				0.005
			) * force.clip(0, 1);

			// the core. a triangle, and then folded -- Ciat-Lonbarde
			// oscillators are raw at the edges and a bandlimited saw
			// crossfade would sound like a synth pretending to be one. the
			// fold amount rides on Timbre and on whatever is modulating it,
			// so a cross-modulated gust buzzes on the peaks of the modulator
			// and settles between them.
			var foldAmt = (timbre.clip(0, 1) + (mod.abs * 0.9)).clip(0, 1.6);
			var tri = LFTri.ar(f);
			var folded = (tri * (1 + (foldAmt * 3.5))).fold2(1);
			// a second triangle a hair off the first, so a single held gust
			// beats slowly against itself instead of sitting perfectly
			// still. this is the whole difference between "a drone" and "an
			// oscillator that is on".
			var shimmer = LFTri.ar(f * 1.0037) * 0.35;
			var core = (folded + shimmer) / 1.35;

			// the fold makes the bright end harsh at exactly the wrong
			// moment, so the low pass opens with Timbre but never all the
			// way: this is a wind instrument, not a filter sweep.
			//
			// tracked off `fBase`, not `f`: LPF only reads its cutoff once
			// per block, so handing it the audio-rate modulated pitch would
			// not sweep the filter smoothly -- it would sample the modulator
			// at the block rate and alias it into a stepped, zippering
			// cutoff. the filter tracks where the note is tuned; the
			// oscillators do the modulating.
			var cutoff = (fBase * (3 + (timbre.clip(0, 1) * 9))).clip(200, 12000);
			var toned = LPF.ar(core, cutoff);
			var sig = LeakDC.ar(toned) * env * amp.clip(0, 1) * 0.3;

			Out.ar(out, sig);
			Out.ar(spaceOut, Pan2.ar(sig, pan.clip(-1, 1)));
		}).add;

		// §2.11 the one delay line every gust is heard through -- "a globally
		// defined delayline that gives it space and ambience". one line for
		// all twelve rather than one each: what it is for is putting the family
		// in a room, and twelve rooms is not a room.
		//
		// a plain delay with the feedback path diffused through a short
		// allpass chain, which is what turns repeats into a tail. the two
		// channels run at slightly different times so the tail widens as it
		// decays rather than staying where the dry signal was. the line's own
		// time is lagged hard: moving a delay time is a tape effect, and an
		// instant jump is a click.
		SynthDef(\wl_gust_space, {
			arg in=0, out=0, mix=0.35, time=0.38, fb=0.45;
			var dry = In.ar(in, 2);
			var t = Lag.kr(time.clip(0.02, 2.0), 0.5);
			var back = LocalIn.ar(2);
			var wet = DelayC.ar(dry + (back * fb.clip(0, 0.92)), 2.1, [t, t * 1.37]);
			// damped in the loop, so each repeat is darker than the last --
			// without this a long feedback setting builds rather than decays.
			wet = LPF.ar(wet, 3200);
			// three allpasses, times chosen mutually prime-ish so the smear
			// does not develop a pitch of its own.
			[0.0131, 0.0271, 0.0353].do({ |dt|
				wet = AllpassC.ar(wet, 0.05, [dt, dt * 1.19], 0.9);
			});
			LocalOut.ar(LeakDC.ar(wet).tanh);
			Out.ar(out, dry + (wet * Lag.kr(mix.clip(0, 1), 0.1) * 1.2));
		}).add;

		// §2.12 an LFO cell: the plainest synth on the panel -- one sine,
		// always running, written to its own `lfoOutBase` tap. there is no amp
		// argument: depth is entirely the cable's own gain (dispatch.lua),
		// same as every other continuous source's cable. `freq` is lagged so a
		// Speed change is a glide, not a click.
		SynthDef(\wl_lfo, { arg out=0, freq=0.2;
			Out.ar(out, SinOsc.ar(Lag.kr(freq.clip(0.02, 20), 0.05)));
		}).add;

		// the grid overhaul's Output row (§2's `O` cells): the only place
		// audio reaches the speakers, and the only thing left in this synth
		// that reads anything other than the sample and gust beds. by default
		// nothing is patched into any of the sixteen `outBus` channels, so a
		// fresh patch is silent until the player cables a voice, a GVOICE
		// cell or an exciter to one -- there is no automatic mix left at all,
		// which is the entire point ("by default none of the voices are wired
		// up to any outputs").
		//
		// each channel also has a LEVEL, read from `lvlBus` -- the mixer
		// page's faders (lib/mixer.lua). that is the channel: everything
		// arriving at that pan position, together, after the fact -- distinct
		// from a cable's own gain, which says how much of one source gets
		// there. lagged, because a fader move on something already sounding
		// is a fade rather than a step; squared, so the bottom of the fader's
		// travel is usable rather than jumping straight to loud.
		//
		// each of the sixteen channels has a FIXED pan position, hard left
		// at channel 0 to hard right at channel 15 (keep this identical to
		// topology.lua's `pan = -1 + 2*(i-1)/15` for O cell i) -- position
		// along the row is what sets pan, not a knob. cabling one source to
		// several O cells sums it at each position it reaches, each at that
		// cable's own gain (patch.lua's ordinary bipolar gain), the same way
		// several cables landing on one mod-path bus already sum.
		SynthDef(\woodland_fx, {
			arg outBus=0, out=0, level=0.8, lvlBus=0, smpIn=0, gustIn=0;
			var chans = In.ar(outBus, nOut);
			var lvls = Lag.kr(In.kr(lvlBus, nOut).clip(0, 1).squared, 0.08);
			var panPos = Array.fill(nOut, { |i| -1 + (2 * i / (nOut - 1)) });
			var dry = Mix.ar(Array.fill(nOut, { |i|
				Pan2.ar(chans[i] * lvls[i], panPos[i]);
			}));
			// §2.5 the sample cells' shared dry bus: each \wl_smp has already
			// applied its own Level knob and its own pan, so all that is left
			// here is the 0.35 headroom factor every voice's own output
			// already carries (Limiter... * amp * 0.35), so a full-level
			// field recording doesn't sit hotter in the mix than a voice at
			// the same knob position.
			var smpDry = In.ar(smpIn, 2) * 0.35;
			// §2.11 the gusts, already panned by cell position and already
			// through their shared delay line -- the one thing here that
			// arrives without a cable. it carries the same 0.35 headroom
			// factor as everything else so a gust at Level 1 sits alongside
			// a voice at Level 1 rather than over it.
			var gustDry = In.ar(gustIn, 2) * 0.35;
			var sig = (dry + smpDry + gustDry) * level;
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

		// §2.5 one sample cell: Rain, Cicada, Thunder or Sea. these four
		// recordings used to be always-on loops with a fader each; they are
		// played now, and the whole instrument is the envelope over the top
		// of them.
		//
		// the buffer still loops underneath, and deliberately so: a trigger
		// restarts it from the top (PlayBuf's own `trigger`), but a second
		// trigger arriving twenty seconds into a forty-second fall finds the
		// recording still running rather than having stopped at its end and
		// gone silent. what is heard is entirely the envelope.
		//
		// Env.perc with the same curve pair \wl_gust uses -- a \sin-ish rise
		// (curve 3) is the shape of weather arriving rather than a ramp, and
		// the -4 fall keeps a forty-second decay from sitting at half volume
		// for twenty of them. the times are seconds and come straight from
		// the cell's own two knobs.
		//
		// Lag on the envelope, not on the output: re-triggering part way up a
		// swell restarts Env.perc from zero, and 5 ms turns the discontinuity
		// that would be into a lift. that is inaudible against an attack
		// measured in seconds.
		//
		// Level is squared for the same reason a fader is, and lagged so
		// turning it while the cell is sounding is a fade.
		SynthDef(\wl_smp, {
			arg out=0, bufnum=0, t_trig=0, force=1,
				atk=1.0, dcy=6.0, speed=1, level=0.7, pan=0;
			var rate = BufRateScale.kr(bufnum) * speed.clip(0.125, 8);
			var sig = PlayBuf.ar(2, bufnum, rate, trigger: t_trig, loop: 1);
			var env = Lag.ar(
				EnvGen.ar(Env.perc(atk.clip(0.02, 20), dcy.clip(0.1, 40), 1, [3, -4]),
				          t_trig),
				0.005
			) * force.clip(0, 1);
			var amp = Lag.kr(level.clip(0, 1).squared, 0.1);
			// mono-summed before panning: these are field recordings, so the
			// two channels are near enough the same thing, and panning a
			// stereo file by cell position is otherwise a contradiction.
			Out.ar(out, Pan2.ar(Mix.ar(sig) * 0.5 * env * amp, pan.clip(-1, 1)));
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
				\modIn, patchBus.index + modInBase + i
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

		// §2.11: always-on, like the voices and the percussion cells. a gust
		// is an instrument that is silent until it is played, not a stream
		// that only exists while cabled -- and its envelope is seconds long,
		// so a synth allocated on the press would be allocated far more
		// often than it would be free. gust.lua's init() pushes every cell's
		// pitch/attack/decay/timbre/cross/level/pan right after this.
		gustSynths = Array.newClear(nGust);
		nGust.do({ |i|
			gustSynths[i] = Synth.new(\wl_gust, [
				\out, patchBus.index + gustOutBase + i,
				\modIn, patchBus.index + gustModBase + i,
				\spaceOut, gustBus.index
			], gVoice);
		});

		// §2.12: always-on, same reasoning as the gusts above -- a free-running
		// sine has nothing to allocate on the press because there is no press;
		// it just sits there until something cables into or out of it.
		// lfo.lua's init() pushes every cell's Speed right after this.
		lfoSynths = Array.newClear(nLfo);
		nLfo.do({ |i|
			lfoSynths[i] = Synth.new(\wl_lfo, [
				\out, patchBus.index + lfoOutBase + i
			], gVoice);
		});

		excSynths = Array.newClear(nExc);
		patchSynths = Dictionary.new;

		// \woodland_fx reads only the Output row now (outBase) -- see its
		// SynthDef comment above. gFx runs after gPatch (the group that
		// writes outBus), so a plain In.ar there sees this block's data.
		// gTap runs after gVoice (where the gusts are) and before gFx (which
		// reads what this writes), which is exactly the order this delay
		// needs -- plain In.ar on both sides, no feedback bus required.
		gustSpaceSynth = Synth.new(\wl_gust_space, [
			\in, gustBus.index,
			\out, gustSpaceBus.index
		], gTap);

		fxSynth = Synth.new(\woodland_fx, [
			\outBus, patchBus.index + outBase,
			\out, context.out_b.index,
			\lvlBus, outLevelBus.index,
			\smpIn, smpBus.index,
			\gustIn, gustSpaceBus.index
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

		// §2.11 the gusts. gust_note is the whole key press in one message
		// -- pitch and force together, because that is what a press is --
		// and gust_pitch is the same pitch without sounding it, for a Scale
		// or transpose change that has to reach a cell mid-swell.
		this.addCommand("gust_note", "iff", { |msg|
			var i = msg[1].asInteger;
			if (i >= 0 and: { i < nGust }) {
				gustSynths[i].set(\freq, msg[2], \force, msg[3], \t_trig, 1);
			};
		});

		this.addCommand("gust_pitch", "if", { |msg|
			var i = msg[1].asInteger;
			if (i >= 0 and: { i < nGust }) { gustSynths[i].set(\freq, msg[2]) };
		});

		this.addCommand("gust_attack", "if", { |msg|
			var i = msg[1].asInteger;
			if (i >= 0 and: { i < nGust }) {
				gustSynths[i].set(\atk, msg[2].clip(0.01, 12));
			};
		});

		this.addCommand("gust_decay", "if", { |msg|
			var i = msg[1].asInteger;
			if (i >= 0 and: { i < nGust }) {
				gustSynths[i].set(\dcy, msg[2].clip(0.05, 30));
			};
		});

		this.addCommand("gust_timbre", "if", { |msg|
			var i = msg[1].asInteger;
			if (i >= 0 and: { i < nGust }) { gustSynths[i].set(\timbre, msg[2]) };
		});

		this.addCommand("gust_cross", "if", { |msg|
			var i = msg[1].asInteger;
			if (i >= 0 and: { i < nGust }) { gustSynths[i].set(\cross, msg[2]) };
		});

		this.addCommand("gust_amp", "if", { |msg|
			var i = msg[1].asInteger;
			if (i >= 0 and: { i < nGust }) { gustSynths[i].set(\amp, msg[2]) };
		});

		// gust_pan(index, v) -- fixed by the cell's column on the Lua side
		// and pushed once at init; there is no knob for it.
		this.addCommand("gust_pan", "if", { |msg|
			var i = msg[1].asInteger;
			if (i >= 0 and: { i < nGust }) {
				gustSynths[i].set(\pan, msg[2].clip(-1, 1));
			};
		});

		// gust_space(mix, time, feedback) -- the one delay line all twelve are
		// heard through, driven from the global page.
		this.addCommand("gust_space", "fff", { |msg|
			gustSpaceSynth.set(\mix, msg[1], \time, msg[2], \fb, msg[3]);
		});

		// §2.12 lfo_rate(index, hz) -- the one knob an LFO cell has.
		this.addCommand("lfo_rate", "if", { |msg|
			var i = msg[1].asInteger;
			if (i >= 0 and: { i < nLfo }) { lfoSynths[i].set(\freq, msg[2].clip(0.02, 20)) };
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

		// not in §8's command list, but E3-with-nothing-held is spec'd as
		// master level (§4.1) and needs somewhere to land.
		this.addCommand("master_level", "f", { |msg|
			fxSynth.set(\level, msg[1]);
		});

		// out_level(index, v) -- §4.1b one Output-row channel's fader
		// (lib/mixer.lua). a control bus rather than a synth argument so one
		// channel can be set without resending the other fifteen.
		this.addCommand("out_level", "if", { |msg|
			var i = msg[1].asInteger;
			if (i >= 0 and: { i < nOut }) {
				outLevelBus.setAt(i, msg[2].clip(0, 1));
			};
		});

		// smp_load(index, path) -- §2.5: one of the four sample cells. Lua
		// sends each absolute path once, at init; Buffer.read is async, so
		// that cell's \wl_smp is only started once the read's completion
		// action fires, and it starts with whatever its knobs have been set
		// to in the meantime (smpArgs). before that -- and if the read never
		// arrives, a missing file, or the offline sc_check with no Lua side
		// to call this at all -- that cell simply makes no sound, which is
		// indistinguishable from its Level being 0. the other three are
		// unaffected either way.
		this.addCommand("smp_load", "is", { |msg|
			var i = msg[1].asInteger;
			var path = msg[2].asString;
			if (i >= 0 and: { i < nSmp }) {
				if (smpBufs[i].notNil) { smpBufs[i].free; smpBufs[i] = nil };
				if (smpSynths[i].notNil) { smpSynths[i].free; smpSynths[i] = nil };
				smpBufs[i] = Buffer.read(server, path, action: { |buf|
					var args = [\out, smpBus.index, \bufnum, buf.bufnum];
					if (smpSynths[i].notNil) { smpSynths[i].free };
					smpArgs[i].keysValuesDo({ |k, v| args = args ++ [k, v] });
					smpSynths[i] = Synth.new(\wl_smp, args, gSrc);
				});
			};
		});

		// every smp_* setter below does the same two things: remember the
		// value in smpArgs whether or not the synth exists yet, and forward
		// it if it does. that is what lets Lua push a whole page of knobs the
		// instant after smp_load, while the buffer read is still in flight.

		this.addCommand("smp_note", "if", { |msg|
			var i = msg[1].asInteger;
			if (i >= 0 and: { i < nSmp } and: { smpSynths[i].notNil }) {
				smpSynths[i].set(\force, msg[2].clip(0, 1), \t_trig, 1);
			};
		});

		this.addCommand("smp_attack", "if", { |msg|
			var i = msg[1].asInteger;
			if (i >= 0 and: { i < nSmp }) {
				smpArgs[i][\atk] = msg[2];
				if (smpSynths[i].notNil) { smpSynths[i].set(\atk, msg[2]) };
			};
		});

		this.addCommand("smp_decay", "if", { |msg|
			var i = msg[1].asInteger;
			if (i >= 0 and: { i < nSmp }) {
				smpArgs[i][\dcy] = msg[2];
				if (smpSynths[i].notNil) { smpSynths[i].set(\dcy, msg[2]) };
			};
		});

		this.addCommand("smp_speed", "if", { |msg|
			var i = msg[1].asInteger;
			if (i >= 0 and: { i < nSmp }) {
				smpArgs[i][\speed] = msg[2];
				if (smpSynths[i].notNil) { smpSynths[i].set(\speed, msg[2]) };
			};
		});

		this.addCommand("smp_level", "if", { |msg|
			var i = msg[1].asInteger;
			if (i >= 0 and: { i < nSmp }) {
				smpArgs[i][\level] = msg[2];
				if (smpSynths[i].notNil) { smpSynths[i].set(\level, msg[2]) };
			};
		});

		this.addCommand("smp_pan", "if", { |msg|
			var i = msg[1].asInteger;
			if (i >= 0 and: { i < nSmp }) {
				smpArgs[i][\pan] = msg[2];
				if (smpSynths[i].notNil) { smpSynths[i].set(\pan, msg[2]) };
			};
		});

	}

	free {
		voiceSynths.do({ |s| if (s.notNil) { s.free } });
		gSynths.do({ |s| if (s.notNil) { s.free } });
		gustSynths.do({ |s| if (s.notNil) { s.free } });
		if (gustSpaceSynth.notNil) { gustSpaceSynth.free };
		lfoSynths.do({ |s| if (s.notNil) { s.free } });
		excSynths.do({ |s| if (s.notNil) { s.free } });
		patchSynths.do({ |s| if (s.notNil) { s.free } });
		if (fxSynth.notNil) { fxSynth.free };
		if (excMeterSynth.notNil) { excMeterSynth.free };
		smpSynths.do({ |s| if (s.notNil) { s.free } });
		smpBufs.do({ |b| if (b.notNil) { b.free } });
		patchBus.free;
		excMeterBus.free;
		outLevelBus.free;
		smpBus.free;
		gustBus.free;
		gustSpaceBus.free;
		gFx.free;
		gTap.free;
		gVoice.free;
		gPatch.free;
		gSrc.free;
	}
}
