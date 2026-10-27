# Keep every ROM initialization receipt visible in the full receiver build.
set_msg_config -id {Synth 8-3876} -limit 10000
# The full receiver shares this desktop with the user's MATLAB sessions.
# Serialize synthesis to avoid replicating its large optimization working set.
set_param general.maxThreads 1
