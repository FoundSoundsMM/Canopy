// headless compile/load check for lib/Engine_Woodland.sc. this is the same
// thing Maiden's compile log tells you on-device, runnable locally instead --
// see the README's "SuperCollider toolchain" section for how sclang and the
// norns-sc quark (which supplies CroneEngine) get installed.
//
// Crone.context is only set once server.waitForBoot's async callback has run
// (see norns-sc's Crone.sc), so this polls for it rather than guessing a
// fixed delay -- a fixed wait raced the boot on first use here and made
// Engine_Woodland:alloc's `context.server` read a nil context.
(
Crone.run();

{
	var tries = 0;
	while ({ Crone.context.isNil and: { tries < 100 } }, {
		0.1.wait;
		tries = tries + 1;
	});

	if (Crone.context.isNil) {
		"WOODLAND ENGINE FAILED: server never finished booting".postln;
		1.exit;
	} {
		try {
			Crone.setEngine("Engine_Woodland");
			1.0.wait;
			"WOODLAND ENGINE LOADED OK".postln;
			0.exit;
		} { |err|
			("WOODLAND ENGINE FAILED: " ++ err.class.name ++ ": " ++ err.errorString).postln;
			1.exit;
		};
	};
}.fork;
)
