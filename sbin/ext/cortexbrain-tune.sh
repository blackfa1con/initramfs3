#!/sbin/busybox sh

#Credits:
# Zacharias.maladroit
# Voku1987
# Collin_ph@xda
# Dorimanx@xda
# Gokhanmoral@xda
# Johnbeetee
# Alucard_24@xda

# TAKE NOTE THAT LINES PRECEDED BY A "#" IS COMMENTED OUT.
#
# This script must be activated after init start =< 25sec or parameters from /sys/* will not be loaded.

# change mode for /tmp/
mount -o remount,rw /;
chmod -R 777 /tmp/;

# ==============================================================
# GLOBAL VARIABLES || without "local" also a variable in a function is global
# ==============================================================

FILE_NAME=$0;
PIDOFCORTEX=$$;
# (since we don't have the recovery source code I can't change the ".siyah" dir, so just leave it there for history)
DATA_DIR=/data/.siyah;
WAS_IN_SLEEP_MODE=1;
NOW_CALL_STATE=0;
USB_POWER=0;
TELE_DATA=init;
# read sd-card size, set via boot
SDCARD_SIZE=$(cat /tmp/sdcard_size);
EXTERNAL_SDCARD_CM=$(mount | grep "/storage/sdcard1" | wc -l);
EXTERNAL_SDCARD_STOCK=$(mount | grep "/storage/extSdCard" | wc -l);

# ==============================================================
# INITIATE
# ==============================================================

# get values from profile
PROFILE=$(cat $DATA_DIR/.active.profile);
. "$DATA_DIR"/"$PROFILE".profile;

# check if dumpsys exist in ROM
if [ -e /system/bin/dumpsys ]; then
	DUMPSYS_STATE=1;
else
	DUMPSYS_STATE=0;
fi;

# set initial vm.dirty vales
echo "600" > /proc/sys/vm/dirty_writeback_centisecs;
echo "3000" > /proc/sys/vm/dirty_expire_centisecs;

# ==============================================================
# FILES FOR VARIABLES || we need this for write variables from child-processes to parent
# ==============================================================

# WIFI HELPER
echo "1" > "$DATA_DIR"/WIFI_HELPER_AWAKE;
echo "1" > "$DATA_DIR"/WIFI_HELPER_TMP;
chmod 666 "$DATA_DIR"/WIFI_HELPER*;
WIFI_HELPER_AWAKE="$DATA_DIR"/WIFI_HELPER_AWAKE;
WIFI_HELPER_TMP="$DATA_DIR"/WIFI_HELPER_TMP;

# MOBILE HELPER
echo "1" > "$DATA_DIR"/MOBILE_HELPER_AWAKE;
echo "1" > "$DATA_DIR"/MOBILE_HELPER_TMP;
chmod 666 "$DATA_DIR"/MOBILE_HELPER*;
MOBILE_HELPER_AWAKE="$DATA_DIR"/MOBILE_HELPER_AWAKE;
MOBILE_HELPER_TMP="$DATA_DIR"/MOBILE_HELPER_TMP;

# ==============================================================
# I/O-TWEAKS
# ==============================================================
IO_TWEAKS()
{
	if [ "$cortexbrain_io" == "on" ]; then

		local i="";

		if [ -e /sys/block/zram0 ]; then
			local ZRM=$(find /sys/block/zram*);
			for i in $ZRM; do
				echo "0" > "$i"/queue/rotational;
				echo "0" > "$i"/queue/iostats;
				echo "1" > "$i"/queue/rq_affinity;
			done;
		fi;

		local MMC=$(find /sys/block/mmc*);
		for i in $MMC; do
			echo "$scheduler" > "$i"/queue/scheduler;
			echo "0" > "$i"/queue/rotational;
			echo "0" > "$i"/queue/iostats;
			echo "1" > "$i"/queue/rq_affinity;
		done;

		if [ -e /sys/block/mmcblk1/queue/scheduler ]; then
			# for now set DEADLINE gov for External SD to fix file transfer via USB
			echo "deadline" > /sys/block/mmcblk1/queue/scheduler;
		fi;

		# This controls how many requests may be allocated
		# in the block layer for read or write requests.
		# Note that the total allocated number may be twice
		# this amount, since it applies only to reads or writes
		# (not the accumulated sum).
		echo "64" > /sys/block/mmcblk0/queue/nr_requests; # default: 128
		if [ -e /sys/block/mmcblk1/queue/nr_requests ]; then
			echo "64" > /sys/block/mmcblk1/queue/nr_requests; # default: 128
		fi;

		# our storage is 16GB, best is 1024KB readahead
		# see https://github.com/Keff/samsung-kernel-msm7x30/commit/a53f8445ff8d947bd11a214ab42340cc6d998600#L1R627
		echo "1024" > /sys/block/mmcblk0/queue/read_ahead_kb;

		if [ -e /sys/block/mmcblk1/queue/read_ahead_kb ]; then
			if [ "$cortexbrain_read_ahead_kb" -eq "0" ]; then

				if [ "$SDCARD_SIZE" -eq "1" ]; then
					echo "256" > /sys/block/mmcblk1/queue/read_ahead_kb;
				elif [ "$SDCARD_SIZE" -eq "4" ]; then
					echo "512" > /sys/block/mmcblk1/queue/read_ahead_kb;
				elif [ "$SDCARD_SIZE" -eq "8" ] || [ "$SDCARD_SIZE" -eq "16" ]; then
					echo "1024" > /sys/block/mmcblk1/queue/read_ahead_kb;
				elif [ "$SDCARD_SIZE" -eq "32" ]; then
					echo "2048" > /sys/block/mmcblk1/queue/read_ahead_kb;
				elif [ "$SDCARD_SIZE" -eq "64" ]; then
					echo "2560" > /sys/block/mmcblk1/queue/read_ahead_kb;
				fi;

			else
				echo "$cortexbrain_read_ahead_kb" > /sys/block/mmcblk1/queue/read_ahead_kb;
			fi;
		fi;

		echo "45" > /proc/sys/fs/lease-break-time;

		log -p i -t "$FILE_NAME" "*** IO_TWEAKS ***: enabled";

		return 1;
	else
		return 0;
	fi;
}
apply_cpu="$2";
if [ "$apply_cpu" != "update" ]; then
	IO_TWEAKS;
fi;

# ==============================================================
# KERNEL-TWEAKS
# ==============================================================
KERNEL_TWEAKS()
{
	if [ "$cortexbrain_kernel_tweaks" == "on" ]; then
		echo "0" > /proc/sys/vm/oom_kill_allocating_task;
		echo "0" > /proc/sys/vm/panic_on_oom;
		echo "30" > /proc/sys/kernel/panic;

		log -p i -t "$FILE_NAME" "*** KERNEL_TWEAKS ***: enabled";
	else
		echo "kernel_tweaks disabled";
	fi;
	if [ "$cortexbrain_memory" == "on" ]; then
		echo "32 32" > /proc/sys/vm/lowmem_reserve_ratio;

		log -p i -t "$FILE_NAME" "*** MEMORY_TWEAKS ***: enabled";
	else
		echo "memory_tweaks disabled";
	fi;
}
apply_cpu="$2";
if [ "$apply_cpu" != "update" ]; then
	KERNEL_TWEAKS;
fi;

# ==============================================================
# SYSTEM-TWEAKS
# ==============================================================
SYSTEM_TWEAKS()
{
	if [ "$cortexbrain_system" == "on" ]; then
		setprop hwui.render_dirty_regions false;
		setprop windowsmgr.max_events_per_sec 240;
		setprop profiler.force_disable_err_rpt 1;
		setprop profiler.force_disable_ulog 1;

		log -p i -t "$FILE_NAME" "*** SYSTEM_TWEAKS ***: enabled";
	else
		echo "system_tweaks disabled";
	fi;
}
apply_cpu="$2";
if [ "$apply_cpu" != "update" ]; then
	SYSTEM_TWEAKS;
fi;

# ==============================================================
# BATTERY-TWEAKS
# ==============================================================
BATTERY_TWEAKS()
{
	if [ "$cortexbrain_battery" == "on" ]; then
		# battery-calibration if battery is full
		local LEVEL=$(cat /sys/class/power_supply/battery/capacity);
		local CURR_ADC=$(cat /sys/class/power_supply/battery/batt_current_adc);
		local BATTFULL=$(cat /sys/class/power_supply/battery/batt_full_check);
		local i="";
		local bus="";

		log -p i -t "$FILE_NAME" "*** BATTERY - LEVEL: $LEVEL - CUR: $CURR_ADC ***";

		if [ "$LEVEL" -eq "100" ] && [ "$BATTFULL" -eq "1" ]; then
			rm -f /data/system/batterystats.bin;
			log -p i -t "$FILE_NAME" "battery-calibration done ...";
		fi;

		# LCD: power-reduce
		if [ -e /sys/class/lcd/panel/power_reduce ]; then
			if [ "$power_reduce" == "on" ]; then
				echo "1" > /sys/class/lcd/panel/power_reduce;
			else
				echo "0" > /sys/class/lcd/panel/power_reduce;
			fi;
		fi;

		# USB: power support
		local POWER_LEVEL=$(ls /sys/bus/usb/devices/*/power/control);
		for i in $POWER_LEVEL; do
			chmod 777 "$i";
			echo "auto" > "$i";
		done;

		local POWER_AUTOSUSPEND=$(ls /sys/bus/usb/devices/*/power/autosuspend);
		for i in $POWER_AUTOSUSPEND; do
			chmod 777 "$i";
			echo "1" > "$i";
		done;

		# BUS: power support
		if [ -e /sys/bus/sdio/devices/mmc2:0001:1/power/control ]; then
			local buslist="spi i2c sdio";
			for bus in $buslist; do
				local POWER_CONTROL=$(ls /sys/bus/"$bus"/devices/*/power/control);
				for i in $POWER_CONTROL; do
					chmod 777 "$i";
					echo "auto" > "$i";
				done;
			done;
		fi;

		log -p i -t "$FILE_NAME" "*** BATTERY_TWEAKS ***: enabled";

		return 1;
	else
		return 0;
	fi;
}
# run this tweak once, if the background-process is disabled
apply_cpu="$2";
if [ "$apply_cpu" != "update" ] || [ "$cortexbrain_background_process" -eq "0" ]; then
	BATTERY_TWEAKS;
fi;

# ==============================================================
# CPU-TWEAKS
# ==============================================================

CPU_HOTPLUG_TWEAKS()
{
	local state="$1";

	local SYSTEM_GOVERNOR=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor);

	# Intelli plug
	if [ -e /sys/module/intelli_plug ]; then
		local intelli_plug_active_tmp="/sys/module/intelli_plug/parameters/intelli_plug_active";
		local intelli_value_tmp=$(cat /sys/module/intelli_plug/parameters/intelli_plug_active);
	else
		intelli_plug_active_tmp="/dev/null";
		intelli_value_tmp="/dev/null";
	fi;

	# Alucard hotplug
	if [ -e /sys/devices/system/cpu/cpufreq/alucard_hotplug ]; then
		local hotplug_enable_tmp="/sys/devices/system/cpu/cpufreq/alucard_hotplug/hotplug_enable";
		local alucard_value_tmp=$(cat /sys/devices/system/cpu/cpufreq/alucard_hotplug/hotplug_enable);
		local cpu_up_rate_tmp="/sys/devices/system/cpu/cpufreq/alucard_hotplug/cpu_up_rate";
		local cpu_down_rate_tmp="/sys/devices/system/cpu/cpufreq/alucard_hotplug/cpu_down_rate";
		local hotplug_freq_fst_tmp="/sys/devices/system/cpu/cpufreq/alucard_hotplug/hotplug_freq_1_1";
		local hotplug_freq_snd_tmp="/sys/devices/system/cpu/cpufreq/alucard_hotplug/hotplug_freq_2_0";
		local up_load_tmp="/sys/devices/system/cpu/cpufreq/alucard_hotplug/hotplug_load_1_1";
		local down_load_tmp="/sys/devices/system/cpu/cpufreq/alucard_hotplug/hotplug_load_2_0";
		local maxcoreslimit_tmp="/sys/devices/system/cpu/cpufreq/alucard_hotplug/maxcoreslimit";
	else
		hotplug_enable_tmp="/dev/null";
		alucard_value_tmp="/dev/null";
		cpu_up_rate_tmp="/dev/null";
		cpu_down_rate_tmp="/dev/null";
		hotplug_freq_fst_tmp="/dev/null";
		hotplug_freq_snd_tmp="/dev/null";
		up_load_tmp="/dev/null";
		down_load_tmp="/dev/null";
		maxcoreslimit_tmp="/dev/null";
	fi;

	if [ "$hotplug_enable" -eq "1" ]; then
		if [ "$SYSTEM_GOVERNOR" == "nightmare" ] || [ "$SYSTEM_GOVERNOR" == "darkness" ] || [ "$SYSTEM_GOVERNOR" == "zzmanX" ]; then
			#disable intelli_plug
			if [ "$intelli_value_tmp" -eq "1" ]; then
				echo "0" > $intelli_plug_active_tmp;
				log -p i -t "$FILE_NAME" "*** CPU_INTELLI_PLUG ***: disabled";
			fi;
			#enable alucard_hotplug
			if [ "$alucard_value_tmp" -eq "0" ]; then
				echo "1" > $hotplug_enable_tmp;
				log -p i -t "$FILE_NAME" "*** CPU_ALUCARD_PLUG ***: enabled";
			fi;
		else
			#enable intelli_plug
			if [ "$intelli_value_tmp" -eq "0" ]; then
				echo "1" > $intelli_plug_active_tmp;
				log -p i -t "$FILE_NAME" "*** CPU_INTELLI_PLUG ***: enabled";
			fi;
			#disable alucard_hotplug
			if [ "$alucard_value_tmp" -eq "1" ]; then
				echo "0" > $hotplug_enable_tmp;
				log -p i -t "$FILE_NAME" "*** CPU_ALUCARD_PLUG ***: disabled";
			fi;
		fi;
	elif [ "$hotplug_enable" -eq "2" ]; then
		#disable intelli_plug
		if [ "$intelli_value_tmp" -eq "1" ]; then
			echo "0" > $intelli_plug_active_tmp;
			log -p i -t "$FILE_NAME" "*** CPU_INTELLI_PLUG ***: disabled";
		fi;
		#enable alucard_hotplug
		if [ "$alucard_value_tmp" -eq "0" ]; then
			echo "1" > $hotplug_enable_tmp;
			log -p i -t "$FILE_NAME" "*** CPU_ALUCARD_PLUG ***: enabled";
		fi;
	elif [ "$hotplug_enable" -eq "3" ]; then
		#enable intelli_plug
		if [ "$intelli_value_tmp" -eq "0" ]; then
			echo "1" > $intelli_plug_active_tmp;
			log -p i -t "$FILE_NAME" "*** CPU_INTELLI_PLUG ***: enabled";
		fi;
		#disable alucard_hotplug
		if [ "$alucard_value_tmp" -eq "1" ]; then
			echo "0" > $hotplug_enable_tmp;
			log -p i -t "$FILE_NAME" "*** CPU_ALUCARD_PLUG ***: disabled";
		fi;
	elif [ "$hotplug_enable" -eq "0" ]; then
		#disable intelli_plug
		if [ "$intelli_value_tmp" -eq "1" ]; then
			echo "0" > $intelli_plug_active_tmp;
			log -p i -t "$FILE_NAME" "*** CPU_INTELLI_PLUG ***: disabled";
		fi;
		#disable alucard_hotplug
		if [ "$alucard_value_tmp" -eq "1" ]; then
			echo "0" > $hotplug_enable_tmp;
			log -p i -t "$FILE_NAME" "*** CPU_ALUCARD_PLUG ***: disabled";
		fi;
	fi;

	# sleep-settings
	if [ "$state" == "sleep" ]; then
		echo "$cpu_up_rate_sleep" > "$cpu_up_rate_tmp";
		echo "$cpu_down_rate_sleep" > "$cpu_down_rate_tmp";
		echo "$hotplug_freq_fst_sleep" > "$hotplug_freq_fst_tmp";
		echo "$hotplug_freq_snd_sleep" > "$hotplug_freq_snd_tmp";
		echo "$up_load_sleep" > "$up_load_tmp";
		echo "$down_load_sleep" > "$down_load_tmp";
		echo "1" > "$maxcoreslimit_tmp";
	# awake-settings
	elif [ "$state" == "awake" ]; then
		echo "$cpu_up_rate" > "$cpu_up_rate_tmp";
		echo "$cpu_down_rate" > "$cpu_down_rate_tmp";
		echo "$hotplug_freq_fst" > "$hotplug_freq_fst_tmp";
		echo "$hotplug_freq_snd" > "$hotplug_freq_snd_tmp";
		echo "$up_load" > "$up_load_tmp";
		echo "$down_load" > "$down_load_tmp";
		echo "2" > "$maxcoreslimit_tmp";
	fi;
}

TWEAK_HOTPLUG_ECO()
{
	local state="$1";

	# Intelli plug
	if [ -e /sys/module/intelli_plug ]; then
		local eco_mode_active_tmp="/sys/module/intelli_plug/parameters/eco_mode_active";
	else
		eco_mode_active_tmp="/dev/null";
	fi;

	if [ "$state" == "sleep" ]; then
		echo "1" > "$eco_mode_active_tmp";
	elif [ "$state" == "awake" ]; then
		echo "0" > "$eco_mode_active_tmp";
	fi;

	log -p i -t "$FILE_NAME" "*** TWEAK_HOTPLUG_ECO: $state ***";
}

CPU_GOV_TWEAKS()
{
	local state="$1";

	if [ "$cortexbrain_cpu" == "on" ]; then
		local SYSTEM_GOVERNOR=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor);

		local sampling_rate_tmp="/sys/devices/system/cpu/cpufreq/$SYSTEM_GOVERNOR/sampling_rate";
		if [ ! -e "$sampling_rate_tmp" ]; then
			sampling_rate_tmp="/dev/null";
		fi;

		local up_threshold_tmp="/sys/devices/system/cpu/cpufreq/$SYSTEM_GOVERNOR/up_threshold";
		if [ ! -e "$up_threshold_tmp" ]; then
			up_threshold_tmp="/dev/null";
		fi;

		local up_threshold_at_min_freq_tmp="/sys/devices/system/cpu/cpufreq/$SYSTEM_GOVERNOR/up_threshold_at_min_freq";
		if [ ! -e "$up_threshold_at_min_freq_tmp" ]; then
			up_threshold_at_min_freq_tmp="/dev/null";
		fi;

		local up_threshold_min_freq_tmp="/sys/devices/system/cpu/cpufreq/$SYSTEM_GOVERNOR/up_threshold_min_freq";
		if [ ! -e "$up_threshold_min_freq_tmp" ]; then
			up_threshold_min_freq_tmp="/dev/null";
		fi;

		local inc_cpu_load_at_min_freq_tmp="/sys/devices/system/cpu/cpufreq/$SYSTEM_GOVERNOR/inc_cpu_load_at_min_freq";
		if [ ! -e "$inc_cpu_load_at_min_freq_tmp" ]; then
			inc_cpu_load_at_min_freq_tmp="/dev/null";
		fi;

		local down_threshold_tmp="/sys/devices/system/cpu/cpufreq/$SYSTEM_GOVERNOR/down_threshold";
		if [ ! -e "$down_threshold_tmp" ]; then
			down_threshold_tmp="/dev/null";
		fi;

		local sampling_up_factor_tmp="/sys/devices/system/cpu/cpufreq/$SYSTEM_GOVERNOR/sampling_up_factor";
		if [ ! -e "$sampling_up_factor_tmp" ]; then
			sampling_up_factor_tmp="/dev/null";
		fi;

		local sampling_down_factor_tmp="/sys/devices/system/cpu/cpufreq/$SYSTEM_GOVERNOR/sampling_down_factor";
		if [ ! -e "$sampling_down_factor_tmp" ]; then
			sampling_down_factor_tmp="/dev/null";
		fi;

		local down_differential_tmp="/sys/devices/system/cpu/cpufreq/$SYSTEM_GOVERNOR/down_differential";
		if [ ! -e "$down_differential_tmp" ]; then
			down_differential_tmp="/dev/null";
		fi;

		local freq_for_responsiveness_tmp="/sys/devices/system/cpu/cpufreq/$SYSTEM_GOVERNOR/freq_for_responsiveness";
		if [ ! -e "$freq_for_responsiveness_tmp" ]; then
			freq_for_responsiveness_tmp="/dev/null";
		fi;

		local freq_responsiveness_tmp="/sys/devices/system/cpu/cpufreq/$SYSTEM_GOVERNOR/freq_responsiveness";
		if [ ! -e "$freq_responsiveness_tmp" ]; then
			freq_responsiveness_tmp="/dev/null";
		fi;

		local freq_for_responsiveness_max_tmp="/sys/devices/system/cpu/cpufreq/$SYSTEM_GOVERNOR/freq_for_responsiveness_max";
		if [ ! -e "$freq_for_responsiveness_max_tmp" ]; then
			freq_for_responsiveness_max_tmp="/dev/null";
		fi;

		local freq_step_at_min_freq_tmp="/sys/devices/system/cpu/cpufreq/$SYSTEM_GOVERNOR/freq_step_at_min_freq";
		if [ ! -e "$freq_step_at_min_freq_tmp" ]; then
			freq_step_at_min_freq_tmp="/dev/null";
		fi;

		local freq_step_tmp="/sys/devices/system/cpu/cpufreq/$SYSTEM_GOVERNOR/freq_step";
		if [ ! -e "$freq_step_tmp" ]; then
			freq_step_tmp="/dev/null";
		fi;

		local freq_step_dec_tmp="/sys/devices/system/cpu/cpufreq/$SYSTEM_GOVERNOR/freq_step_dec";
		if [ ! -e "$freq_step_dec_tmp" ]; then
			freq_step_dec_tmp="/dev/null";
		fi;

		local freq_step_dec_at_max_freq_tmp="/sys/devices/system/cpu/cpufreq/$SYSTEM_GOVERNOR/freq_step_dec_at_max_freq";
		if [ ! -e "$freq_step_dec_at_max_freq_tmp" ]; then
			freq_step_dec_at_max_freq_tmp="/dev/null";
		fi;

		local up_sf_step_tmp="/sys/devices/system/cpu/cpufreq/$SYSTEM_GOVERNOR/up_sf_step";
		if [ ! -e "$up_sf_step_tmp" ]; then
			up_sf_step_tmp="/dev/null";
		fi;

		local down_sf_step_tmp="/sys/devices/system/cpu/cpufreq/$SYSTEM_GOVERNOR/down_sf_step";
		if [ ! -e "$down_sf_step_tmp" ]; then
			down_sf_step_tmp="/dev/null";
		fi;

		local inc_cpu_load_tmp="/sys/devices/system/cpu/cpufreq/$SYSTEM_GOVERNOR/inc_cpu_load";
		if [ ! -e "$inc_cpu_load_tmp" ]; then
			inc_cpu_load_tmp="/dev/null";
		fi;

		local dec_cpu_load_tmp="/sys/devices/system/cpu/cpufreq/$SYSTEM_GOVERNOR/dec_cpu_load";
		if [ ! -e "$dec_cpu_load_tmp" ]; then
			dec_cpu_load_tmp="/dev/null";
		fi;

		local freq_up_brake_at_min_freq_tmp="/sys/devices/system/cpu/cpufreq/$SYSTEM_GOVERNOR/freq_up_brake_at_min_freq";
		if [ ! -e "$freq_up_brake_at_min_freq_tmp" ]; then
			freq_up_brake_at_min_freq_tmp="/dev/null";
		fi;

		local freq_up_brake_tmp="/sys/devices/system/cpu/cpufreq/$SYSTEM_GOVERNOR/freq_up_brake";
		if [ ! -e "$freq_up_brake_tmp" ]; then
			freq_up_brake_tmp="/dev/null";
		fi;

		local force_freqs_step_tmp="/sys/devices/system/cpu/cpufreq/$SYSTEM_GOVERNOR/force_freqs_step";
		if [ ! -e "$force_freqs_step_tmp" ]; then
			force_freqs_step_tmp="/dev/null";
		fi;

		# merge up_threshold_at_min_freq & up_threshold_min_freq => up_threshold_at_min_freq_tmp
		if [ "$up_threshold_at_min_freq_tmp" == "/dev/null" ] && [ "$up_threshold_min_freq_tmp" != "/dev/null" ]; then
			up_threshold_at_min_freq_tmp="$up_threshold_min_freq_tmp";
		fi;

		# merge freq_for_responsiveness_tmp & freq_responsiveness_tmp => freq_for_responsiveness_tmp
		if [ "$freq_for_responsiveness_tmp" == "/dev/null" ] && [ "$freq_responsiveness_tmp" != "/dev/null" ]; then
			freq_for_responsiveness_tmp="$freq_responsiveness_tmp";
		fi;

		local sampling_down_max_mom_tmp="/sys/devices/system/cpu/cpufreq/$SYSTEM_GOVERNOR/sampling_down_max_mom";
		if [ ! -e "$sampling_down_max_mom_tmp" ]; then
			sampling_down_max_mom_tmp="/dev/null";
		fi;

		local sampling_down_mom_sens_tmp="/sys/devices/system/cpu/cpufreq/$SYSTEM_GOVERNOR/sampling_down_mom_sens";
		if [ ! -e "$sampling_down_mom_sens_tmp" ]; then
			sampling_down_mom_sens_tmp="/dev/null";
		fi;

		local up_threshold_hp_fst_tmp="/sys/devices/system/cpu/cpufreq/$SYSTEM_GOVERNOR/up_threshold_hotplug1";
		if [ ! -e "$up_threshold_hp_fst_tmp" ]; then
			up_threshold_hp_fst_tmp="/dev/null";
		fi;

		local down_threshold_hp_fst_tmp="/sys/devices/system/cpu/cpufreq/$SYSTEM_GOVERNOR/down_threshold_hotplug1";
		if [ ! -e "$down_threshold_hp_fst_tmp" ]; then
			down_threshold_hp_fst_tmp="/dev/null";
		fi;

		local up_threshold_hp_freq_fst_tmp="/sys/devices/system/cpu/cpufreq/$SYSTEM_GOVERNOR/up_threshold_hotplug_freq1";
		if [ ! -e "$up_threshold_hp_freq_fst_tmp" ]; then
			up_threshold_hp_freq_fst_tmp="/dev/null";
		fi;

		local down_threshold_hp_freq_fst_tmp="/sys/devices/system/cpu/cpufreq/$SYSTEM_GOVERNOR/down_threshold_hotplug_freq1";
		if [ ! -e "$down_threshold_hp_freq_fst_tmp" ]; then
			down_threshold_hp_freq_fst_tmp="/dev/null";
		fi;

		local smooth_up_tmp="/sys/devices/system/cpu/cpufreq/$SYSTEM_GOVERNOR/smooth_up";
		if [ ! -e "$smooth_up_tmp" ]; then
			smooth_up_tmp="/dev/null";
		fi;

		local freq_limit_tmp="/sys/devices/system/cpu/cpufreq/$SYSTEM_GOVERNOR/freq_limit";
		if [ ! -e "$freq_limit_tmp" ]; then
			freq_limit_tmp="/dev/null";
		fi;

		local fast_scaling_tmp="/sys/devices/system/cpu/cpufreq/$SYSTEM_GOVERNOR/fast_scaling";
		if [ ! -e "$fast_scaling_tmp" ]; then
			fast_scaling_tmp="/dev/null";
		fi;

		local early_demand_tmp="/sys/devices/system/cpu/cpufreq/$SYSTEM_GOVERNOR/early_demand";
		if [ ! -e "$early_demand_tmp" ]; then
			early_demand_tmp="/dev/null";
		fi;

		local grad_up_threshold_tmp="/sys/devices/system/cpu/cpufreq/$SYSTEM_GOVERNOR/grad_up_threshold";
		if [ ! -e "$grad_up_threshold_tmp" ]; then
			grad_up_threshold_tmp="/dev/null";
		fi;

		local disable_hotplug_tmp="/sys/devices/system/cpu/cpufreq/$SYSTEM_GOVERNOR/disable_hotplug";
		if [ ! -e "$disable_hotplug_tmp" ]; then
			disable_hotplug_tmp="/dev/null";
		fi;

		local boostfreq_tmp="/sys/devices/system/cpu/cpufreq/$SYSTEM_GOVERNOR/boostfreq";
		if [ ! -e "$boostfreq_tmp" ]; then
			boostfreq_tmp="/dev/null";
		fi;

		# sleep-settings
		if [ "$state" == "sleep" ]; then
			echo "$sampling_rate_sleep" > "$sampling_rate_tmp";
			echo "$up_threshold_sleep" > "$up_threshold_tmp";
			echo "$up_threshold_at_min_freq_sleep" > "$up_threshold_at_min_freq_tmp";
			echo "$inc_cpu_load_at_min_freq_sleep" > "$inc_cpu_load_at_min_freq_tmp";
			echo "$down_threshold_sleep" > "$down_threshold_tmp";
			echo "$sampling_up_factor_sleep" > "$sampling_up_factor_tmp";
			echo "$sampling_down_factor_sleep" > "$sampling_down_factor_tmp";
			echo "$down_differential_sleep" > "$down_differential_tmp";
			echo "$freq_step_at_min_freq_sleep" > "$freq_step_at_min_freq_tmp";
			echo "$freq_step_sleep" > "$freq_step_tmp";
			echo "$freq_step_dec_sleep" > "$freq_step_dec_tmp";
			echo "$freq_step_dec_at_max_freq_sleep" > "$freq_step_dec_at_max_freq_tmp";
			echo "$freq_for_responsiveness_sleep" > "$freq_for_responsiveness_tmp";
			echo "$freq_for_responsiveness_max_sleep" > "$freq_for_responsiveness_max_tmp";
			echo "$up_sf_step_sleep" > "$up_sf_step_tmp";
			echo "$down_sf_step_sleep" > "$down_sf_step_tmp";
			echo "$inc_cpu_load_sleep" > "$inc_cpu_load_tmp";
			echo "$dec_cpu_load_sleep" > $dec_cpu_load_tmp;
			echo "$freq_up_brake_at_min_freq_sleep" > "$freq_up_brake_at_min_freq_tmp";
			echo "$freq_up_brake_sleep" > "$freq_up_brake_tmp";
			echo "$force_freqs_step" > "$force_freqs_step_tmp";
			echo "$sampling_down_max_mom_sleep" > "$sampling_down_max_mom_tmp";
			echo "$sampling_down_mom_sens_sleep" > "$sampling_down_mom_sens_tmp";
			echo "$up_threshold_hp_fst_sleep" > "$up_threshold_hp_fst_tmp";
			echo "$down_threshold_hp_fst_sleep" > "$down_threshold_hp_fst_tmp";
			echo "$up_threshold_hp_freq_fst_sleep" > "$up_threshold_hp_freq_fst_tmp";
			echo "$down_threshold_hp_freq_fst_sleep" > "$down_threshold_hp_freq_fst_tmp";
			echo "$smooth_up_sleep" > "$smooth_up_tmp";
			echo "$freq_limit_sleep" > "$freq_limit_tmp";
			echo "$fast_scaling_sleep" > "$fast_scaling_tmp";
			echo "$early_demand_sleep" > "$early_demand_tmp";
			echo "$grad_up_threshold_sleep" > "$grad_up_threshold_tmp";
			echo "$disable_hotplug_sleep" > "$disable_hotplug_tmp";
			CPU_HOTPLUG_TWEAKS "sleep";
		# awake-settings
		elif [ "$state" == "awake" ]; then
			CPU_HOTPLUG_TWEAKS "awake";
			echo "$sampling_rate" > "$sampling_rate_tmp";
			echo "$up_threshold" > "$up_threshold_tmp";
			echo "$up_threshold_at_min_freq" > "$up_threshold_at_min_freq_tmp";
			echo "$inc_cpu_load_at_min_freq" > "$inc_cpu_load_at_min_freq_tmp";
			echo "$down_threshold" > "$down_threshold_tmp";
			echo "$sampling_up_factor" > "$sampling_up_factor_tmp";
			echo "$sampling_down_factor" > "$sampling_down_factor_tmp";
			echo "$down_differential" > "$down_differential_tmp";
			echo "$freq_step_at_min_freq" > "$freq_step_at_min_freq_tmp";
			if [ "$SYSTEM_GOVERNOR" == "zzmanX" ]; then
				echo "5" > "$freq_step_tmp";
			else
				echo "$freq_step" > "$freq_step_tmp";
			fi;
			echo "$freq_step_dec" > "$freq_step_dec_tmp";
			echo "$freq_step_dec_at_max_freq" > "$freq_step_dec_at_max_freq_tmp";
			echo "$freq_for_responsiveness" > "$freq_for_responsiveness_tmp";
			echo "$freq_for_responsiveness_max" > "$freq_for_responsiveness_max_tmp";
			echo "$up_sf_step" > "$up_sf_step_tmp";
			echo "$down_sf_step" > "$down_sf_step_tmp";
			echo "$inc_cpu_load" > "$inc_cpu_load_tmp";
			echo "$dec_cpu_load" > "$dec_cpu_load_tmp";
			echo "$freq_up_brake_at_min_freq" > "$freq_up_brake_at_min_freq_tmp";
			echo "$freq_up_brake" > "$freq_up_brake_tmp";
			echo "$force_freqs_step" > "$force_freqs_step_tmp";
			echo "$sampling_down_max_mom" > "$sampling_down_max_mom_tmp";
			echo "$sampling_down_mom_sens" > "$sampling_down_mom_sens_tmp";
			echo "$up_threshold_hp_fst" > "$up_threshold_hp_fst_tmp";
			echo "$down_threshold_hp_fst" > "$down_threshold_hp_fst_tmp";
			echo "$up_threshold_hp_freq_fst" > "$up_threshold_hp_freq_fst_tmp";
			echo "$down_threshold_hp_freq_fst" > "$down_threshold_hp_freq_fst_tmp";
			echo "$smooth_up" > "$smooth_up_tmp";
			echo "$freq_limit" > "$freq_limit_tmp";
			echo "$fast_scaling" > "$fast_scaling_tmp";
			echo "$early_demand" > "$early_demand_tmp";
			echo "$grad_up_threshold" > "$grad_up_threshold_tmp";
			echo "$disable_hotplug" > "$disable_hotplug_tmp";
			echo "$boostfreq" > "$boostfreq_tmp";
		fi;

		log -p i -t "$FILE_NAME" "*** CPU_GOV_TWEAKS: $state ***: enabled";

		return 1;
	else
		return 0;
	fi;
}
# this needed for cpu tweaks apply from STweaks in real time
apply_cpu="$2";
if [ "$apply_cpu" == "update" ] || [ "$cortexbrain_background_process" -eq "0" ]; then
	CPU_GOV_TWEAKS "awake";
fi;

# ==============================================================
# MEMORY-TWEAKS
# ==============================================================
MEMORY_TWEAKS()
{
	if [ "$cortexbrain_memory" == "on" ]; then
		echo "$dirty_background_ratio" > /proc/sys/vm/dirty_background_ratio; # default: 10
		echo "$dirty_ratio" > /proc/sys/vm/dirty_ratio; # default: 20
		echo "4" > /proc/sys/vm/min_free_order_shift; # default: 4
		echo "1" > /proc/sys/vm/overcommit_memory; # default: 1
		echo "50" > /proc/sys/vm/overcommit_ratio; # default: 50
		echo "3" > /proc/sys/vm/page-cluster; # default: 3
		echo "8192" > /proc/sys/vm/min_free_kbytes;

		log -p i -t "$FILE_NAME" "*** MEMORY_TWEAKS ***: enabled";

		return 1;
	else
		return 0;
	fi;
}
apply_cpu="$2";
if [ "$apply_cpu" != "update" ]; then
	MEMORY_TWEAKS;
fi;

# ==============================================================
# TCP-TWEAKS
# ==============================================================
TCP_TWEAKS()
{
	if [ "$cortexbrain_tcp" == "on" ]; then
		echo "0" > /proc/sys/net/ipv4/tcp_timestamps;
		echo "1" > /proc/sys/net/ipv4/tcp_rfc1337;
		echo "1" > /proc/sys/net/ipv4/tcp_workaround_signed_windows;
		echo "1" > /proc/sys/net/ipv4/tcp_low_latency;
		echo "1" > /proc/sys/net/ipv4/tcp_mtu_probing;
		echo "2" > /proc/sys/net/ipv4/tcp_frto_response;
		echo "1" > /proc/sys/net/ipv4/tcp_no_metrics_save;
		echo "1" > /proc/sys/net/ipv4/tcp_tw_reuse;
		echo "1" > /proc/sys/net/ipv4/tcp_tw_recycle;
		echo "30" > /proc/sys/net/ipv4/tcp_fin_timeout;
		echo "0" > /proc/sys/net/ipv4/tcp_ecn;
		echo "5" > /proc/sys/net/ipv4/tcp_keepalive_probes;
		echo "40" > /proc/sys/net/ipv4/tcp_keepalive_intvl;
		echo "2500" > /proc/sys/net/core/netdev_max_backlog;
		echo "1" > /proc/sys/net/ipv4/route/flush;

		log -p i -t "$FILE_NAME" "*** TCP_TWEAKS ***: enabled";
	else
		echo "1" > /proc/sys/net/ipv4/tcp_timestamps;
		echo "0" > /proc/sys/net/ipv4/tcp_rfc1337;
		echo "0" > /proc/sys/net/ipv4/tcp_workaround_signed_windows;
		echo "0" > /proc/sys/net/ipv4/tcp_low_latency;
		echo "0" > /proc/sys/net/ipv4/tcp_mtu_probing;
		echo "0" > /proc/sys/net/ipv4/tcp_frto_response;
		echo "0" > /proc/sys/net/ipv4/tcp_no_metrics_save;
		echo "0" > /proc/sys/net/ipv4/tcp_tw_reuse;
		echo "0" > /proc/sys/net/ipv4/tcp_tw_recycle;
		echo "60" > /proc/sys/net/ipv4/tcp_fin_timeout;
		echo "2" > /proc/sys/net/ipv4/tcp_ecn;
		echo "9" > /proc/sys/net/ipv4/tcp_keepalive_probes;
		echo "75" > /proc/sys/net/ipv4/tcp_keepalive_intvl;
		echo "1000" > /proc/sys/net/core/netdev_max_backlog;
		echo "0" > /proc/sys/net/ipv4/route/flush;

		log -p i -t "$FILE_NAME" "*** TCP_TWEAKS ***: disabled";
	fi;

	if [ "$cortexbrain_tcp_ram" == "on" ]; then
		echo "4194304" > /proc/sys/net/core/wmem_max;
		echo "4194304" > /proc/sys/net/core/rmem_max;
		echo "20480" > /proc/sys/net/core/optmem_max;
		echo "4096 87380 4194304" > /proc/sys/net/ipv4/tcp_wmem;
		echo "4096 87380 4194304" > /proc/sys/net/ipv4/tcp_rmem;

		log -p i -t "$FILE_NAME" "*** TCP_RAM_TWEAKS ***: enabled";
	else
		echo "131071" > /proc/sys/net/core/wmem_max;
		echo "131071" > /proc/sys/net/core/rmem_max;
		echo "10240" > /proc/sys/net/core/optmem_max;
		echo "4096 16384 262144" > /proc/sys/net/ipv4/tcp_wmem;
		echo "4096 87380 704512" > /proc/sys/net/ipv4/tcp_rmem;

		log -p i -t "$FILE_NAME" "*** TCP_RAM_TWEAKS ***: disable";
	fi;
}
apply_cpu="$2";
if [ "$apply_cpu" != "update" ]; then
	TCP_TWEAKS;
fi;

# ==============================================================
# FIREWALL-TWEAKS
# ==============================================================
FIREWALL_TWEAKS()
{
	if [ "$cortexbrain_firewall" == "on" ]; then
		# ping/icmp protection
		echo "1" > /proc/sys/net/ipv4/icmp_echo_ignore_broadcasts;
		echo "1" > /proc/sys/net/ipv4/icmp_echo_ignore_all;
		echo "1" > /proc/sys/net/ipv4/icmp_ignore_bogus_error_responses;

		log -p i -t "$FILE_NAME" "*** FIREWALL_TWEAKS ***: enabled";

		return 1;
	else
		return 0;
	fi;
}
apply_cpu="$2";
if [ "$apply_cpu" != "update" ]; then
	FIREWALL_TWEAKS;
fi;

# ==============================================================
# GLOBAL-FUNCTIONS
# ==============================================================

WIFI_SET()
{
	local state="$1";

	if [ "$state" == "off" ]; then
		service call wifi 13 i32 0 > /dev/null;
		svc wifi disable;
		echo "1" > "$WIFI_HELPER_AWAKE";
	elif [ "$state" == "on" ]; then
		service call wifi 13 i32 1 > /dev/null;
		svc wifi enable;
	fi;

	log -p i -t "$FILE_NAME" "*** WIFI ***: $state";
}

WIFI()
{
	local state="$1";

	if [ "$state" == "sleep" ]; then
		if [ "$cortexbrain_auto_tweak_wifi" == "on" ]; then
			if [ -e /sys/module/dhd/initstate ]; then
				if [ "$cortexbrain_auto_tweak_wifi_sleep_delay" -eq "0" ]; then
					WIFI_SET "off";
				else
					(
						echo "0" > "$WIFI_HELPER_TMP";
						# screen time out but user want to keep it on and have wifi
						sleep 10;
						if [ "$(cat "$WIFI_HELPER_TMP")" -eq "0" ]; then
							# user did not turned screen on, so keep waiting
							local SLEEP_TIME_WIFI=$((cortexbrain_auto_tweak_wifi_sleep_delay - 10));
							log -p i -t "$FILE_NAME" "*** DISABLE_WIFI $cortexbrain_auto_tweak_wifi_sleep_delay Sec Delay Mode ***";
							sleep "$SLEEP_TIME_WIFI";
							if [ "$(cat "$WIFI_HELPER_TMP")" -eq "0" ]; then
								# user left the screen off, then disable wifi
								WIFI_SET "off";
							fi;
						fi;
					)&
				fi;
			else
				echo "0" > "$WIFI_HELPER_AWAKE";
			fi;
		fi;
	elif [ "$state" == "awake" ]; then
		if [ "$cortexbrain_auto_tweak_wifi" == "on" ]; then
			echo "1" > "$WIFI_HELPER_TMP";
			if [ "$(cat "$WIFI_HELPER_AWAKE")" -eq "1" ]; then
				WIFI_SET "on";
			fi;
		fi;
	fi;
}

MOBILE_DATA_SET()
{
	local state="$1";

	if [ "$state" == "off" ]; then
		svc data disable;
		echo "1" > "$MOBILE_HELPER_AWAKE";
	elif [ "$state" == "on" ]; then
		svc data enable;
	fi;

	log -p i -t "$FILE_NAME" "*** MOBILE DATA ***: $state";
}

MOBILE_DATA_STATE()
{
	DATA_STATE_CHECK=0;

	if [ "$DUMPSYS_STATE" -eq "1" ]; then
		local DATA_STATE=$(echo "$TELE_DATA" | awk '/mDataConnectionState/ {print $1}');

		if [ "$DATA_STATE" != "mDataConnectionState=0" ]; then
			DATA_STATE_CHECK=1;
		fi;
	fi;
}

MOBILE_DATA()
{
	local state="$1";

	if [ "$cortexbrain_auto_tweak_mobile" == "on" ]; then
		if [ "$state" == "sleep" ]; then
			MOBILE_DATA_STATE;
			if [ "$DATA_STATE_CHECK" -eq "1" ]; then
				if [ "$cortexbrain_auto_tweak_mobile_sleep_delay" -eq "0" ]; then
					MOBILE_DATA_SET "off";
				else
					(
						echo "0" > "$MOBILE_HELPER_TMP";
						# screen time out but user want to keep it on and have mobile data
						sleep 10;
						if [ "$(cat "$MOBILE_HELPER_TMP")" -eq "0" ]; then
							# user did not turned screen on, so keep waiting
							local SLEEP_TIME_DATA=$((cortexbrain_auto_tweak_mobile_sleep_delay - 10));
							log -p i -t "$FILE_NAME" "*** DISABLE_MOBILE $cortexbrain_auto_tweak_mobile_sleep_delay Sec Delay Mode ***";
							sleep "$SLEEP_TIME_DATA";
							if [ "$(cat "$MOBILE_HELPER_TMP")" -eq "0" ]; then
								# user left the screen off, then disable mobile data
								MOBILE_DATA_SET "off";
							fi;
						fi;
					)&
				fi;
			else
				echo "0" > "$MOBILE_HELPER_AWAKE";
			fi;
		elif [ "$state" == "awake" ]; then
			echo "1" > "$MOBILE_HELPER_TMP";
			if [ "$(cat "$MOBILE_HELPER_AWAKE")" -eq "1" ]; then
				MOBILE_DATA_SET "on";
			fi;
		fi;
	fi;
}

LOGGER()
{
	local state="$1";

	if [ "$state" == "awake" ]; then
		if [ "$android_logger" == "auto" ] || [ "$android_logger" == "debug" ]; then
			echo "1" > /sys/module/logger/parameters/log_enabled;
		elif [ "$android_logger" == "disabled" ]; then
			echo "0" > /sys/module/logger/parameters/log_enabled;
		fi;
	elif [ "$state" == "sleep" ]; then
		if [ "$android_logger" == "auto" ] || [ "$android_logger" == "disabled" ]; then
			echo "0" > /sys/module/logger/parameters/log_enabled;
		fi;
	fi;

	log -p i -t "$FILE_NAME" "*** LOGGER ***: $state";
}

GESTURES()
{
	local state="$1";

	if [ "$state" == "awake" ]; then
		if [ "$gesture_tweak" == "on" ]; then
			pkill -f "/data/gesture_set.sh";
			pkill -f "/sys/devices/virtual/misc/touch_gestures/wait_for_gesture";
			nohup /sbin/busybox sh /data/gesture_set.sh;
		fi;
	elif [ "$state" == "sleep" ]; then
		if [ "$(pgrep -f "/data/gesture_set.sh" | wc -l)" != "0" ] || [ "$(pgrep -f "/sys/devices/virtual/misc/touch_gestures/wait_for_gesture" | wc -l)" != "0" ] || [ "$gesture_tweak" == "off" ]; then
			pkill -f "/data/gesture_set.sh";
			pkill -f "/sys/devices/virtual/misc/touch_gestures/wait_for_gesture";
		fi;
	fi;

	log -p i -t "$FILE_NAME" "*** GESTURE ***: $state";
}

# mount sdcard and emmc, if usb mass storage is used
MOUNT_SD_CARD()
{
	if [ "$auto_mount_sd" == "on" ]; then
		echo "/dev/block/vold/259:3" > /sys/devices/virtual/android_usb/android0/f_mass_storage/lun0/file;
		if [ -e /dev/block/vold/179:9 ]; then
			echo "/dev/block/vold/179:9" > /sys/devices/virtual/android_usb/android0/f_mass_storage/lun1/file;
		fi;

		log -p i -t "$FILE_NAME" "*** MOUNT_SD_CARD ***";
	fi;
}
# run dual mount on boot
apply_cpu="$2";
if [ "$apply_cpu" != "update" ]; then
	MOUNT_SD_CARD;
fi;

MALI_TIMEOUT()
{
	local state="$1";

	if [ "$state" == "awake" ]; then
		echo "$mali_gpu_utilization_timeout" > /sys/module/mali/parameters/mali_gpu_utilization_timeout;
	elif [ "$state" == "sleep" ]; then
		echo "100" > /sys/module/mali/parameters/mali_gpu_utilization_timeout;
	elif [ "$state" == "wake_boost" ]; then
		echo "100" > /sys/module/mali/parameters/mali_gpu_utilization_timeout;
	fi;

	log -p i -t "$FILE_NAME" "*** MALI_TIMEOUT: $state ***";
}

BUS_THRESHOLD()
{
	local state="$1";

	if [ "$state" == "awake" ]; then
		echo "$busfreq_up_threshold" > /sys/devices/system/cpu/cpufreq/busfreq_up_threshold;
	elif [ "$state" == "sleep" ]; then
		echo "$busfreq_up_threshold_sleep" > /sys/devices/system/cpu/cpufreq/busfreq_up_threshold;
	elif [ "$state" == "wake_boost" ]; then
		echo "25" > /sys/devices/system/cpu/cpufreq/busfreq_up_threshold;
	fi;

	log -p i -t "$FILE_NAME" "*** BUS_THRESHOLD: $state ***";
}

# ==============================================================
# ECO-TWEAKS
# ==============================================================
ECO_TWEAKS()
{
	if [ "$cortexbrain_eco" == "on" ]; then
		local LEVEL=$(cat /sys/class/power_supply/battery/capacity);
		if [ "$LEVEL" -le "$cortexbrain_eco_level" ]; then
			TWEAK_HOTPLUG_ECO "sleep";
			CPU_GOV_TWEAKS "sleep";
			log -p i -t "$FILE_NAME" "*** AWAKE: ECO-Mode ***";
		else
			log -p i -t "$FILE_NAME" "*** AWAKE: Normal-Mode ***";
		fi;

		log -p i -t "$FILE_NAME" "*** ECO_TWEAKS ***: enabled";
	else
		log -p i -t "$FILE_NAME" "*** ECO_TWEAKS ***: disabled";
		log -p i -t "$FILE_NAME" "*** AWAKE: Normal-Mode ***";
	fi;
}

CENTRAL_CPU_FREQ()
{
	local state="$1";

	local SYSTEM_GOVERNOR=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor);

	local min_freq_limit_0_tmp="/sys/devices/system/cpu/cpufreq/$SYSTEM_GOVERNOR/min_freq_limit_0";
	if [ ! -e "$min_freq_limit_0_tmp" ]; then
		min_freq_limit_0_tmp="/dev/null";
	fi;
	local min_freq_limit_1_tmp="/sys/devices/system/cpu/cpufreq/$SYSTEM_GOVERNOR/min_freq_limit_1";
	if [ ! -e "$min_freq_limit_1_tmp" ]; then
		min_freq_limit_1_tmp="/dev/null";
	fi;
	local max_freq_limit_0_tmp="/sys/devices/system/cpu/cpufreq/$SYSTEM_GOVERNOR/max_freq_limit_0";
	if [ ! -e "$max_freq_limit_0_tmp" ]; then
		max_freq_limit_0_tmp="/dev/null";
	fi;
	local max_freq_limit_1_tmp="/sys/devices/system/cpu/cpufreq/$SYSTEM_GOVERNOR/max_freq_limit_1";
	if [ ! -e "$max_freq_limit_1_tmp" ]; then
		max_freq_limit_1_tmp="/dev/null";
	fi;

	if [ "$cortexbrain_cpu" == "on" ]; then
		if [ "$state" == "wake_boost" ] && [ "$wakeup_boost" -ge "0" ]; then
			if [ "$scaling_max_freq" -eq "1000000" ] && [ "$scaling_max_freq_oc" -gt "1000000" ]; then
				MAX_FREQ="$scaling_max_freq_oc";
			else
				MAX_FREQ="$scaling_max_freq";
			fi;
			if [ "$MAX_FREQ" -gt "1000000" ]; then
				echo "$MAX_FREQ" > "$max_freq_limit_0_tmp";
				echo "$MAX_FREQ" > "$max_freq_limit_1_tmp";
				echo "$MAX_FREQ" > "$min_freq_limit_0_tmp";
				echo "$MAX_FREQ" > "$min_freq_limit_1_tmp";
				echo "$MAX_FREQ" > /sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq;
				echo "$MAX_FREQ" > /sys/devices/system/cpu/cpu0/cpufreq/scaling_min_freq;
			else
				echo "1200000" > "$max_freq_limit_0_tmp";
				echo "1200000" > "$max_freq_limit_1_tmp";
				echo "1200000" > "$min_freq_limit_0_tmp";
				echo "1200000" > "$min_freq_limit_1_tmp";
				echo "1200000" > /sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq;
				echo "1200000" > /sys/devices/system/cpu/cpu0/cpufreq/scaling_min_freq;
			fi;
		elif [ "$state" == "awake_normal" ]; then
			if [ "$scaling_max_freq" -eq "1000000" ] && [ "$scaling_max_freq_oc" -gt "1000000" ]; then
				WAKE_MAX_FREQ="$scaling_max_freq_oc";
			else
				WAKE_MAX_FREQ="$scaling_max_freq";
			fi;
			echo "$scaling_min_freq" > "$min_freq_limit_0_tmp";
			echo "$scaling_min_freq" > "$min_freq_limit_1_tmp";
			echo "$scaling_min_freq" > /sys/devices/system/cpu/cpu0/cpufreq/scaling_min_freq;
			echo "$WAKE_MAX_FREQ" > "$max_freq_limit_0_tmp";
			echo "$WAKE_MAX_FREQ" > "$max_freq_limit_1_tmp";
			echo "$WAKE_MAX_FREQ" > /sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq;
		elif [ "$state" == "standby_freq" ]; then
			echo "$standby_freq" > "$min_freq_limit_0_tmp";
			echo "$standby_freq" > "$min_freq_limit_1_tmp";
			echo "$standby_freq" > /sys/devices/system/cpu/cpu0/cpufreq/scaling_min_freq;
		elif [ "$state" == "sleep_freq" ]; then
			echo "$scaling_min_suspend_freq" > "$min_freq_limit_0_tmp";
			echo "$scaling_min_suspend_freq" > "$min_freq_limit_1_tmp";
			echo "$scaling_max_suspend_freq" > "$max_freq_limit_0_tmp";
			echo "$scaling_max_suspend_freq" > "$max_freq_limit_1_tmp";
			echo "$scaling_min_suspend_freq" > /sys/devices/system/cpu/cpu0/cpufreq/scaling_min_freq;
			echo "$scaling_max_suspend_freq" > /sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq;
		elif [ "$state" == "sleep_call" ]; then
			echo "$standby_freq" > "$min_freq_limit_0_tmp";
			echo "$standby_freq" > "$min_freq_limit_1_tmp";
			echo "$standby_freq" > /sys/devices/system/cpu/cpu0/cpufreq/scaling_min_freq;
			# brain cooking prevention during call
			echo "800000" > "$max_freq_limit_0_tmp";
			echo "800000" > "$max_freq_limit_1_tmp";
			echo "800000" > /sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq;
		else
			# if wakeup boost is disabled 0 or -1
			if [ "$scaling_max_freq" -eq "1000000" ] && [ "$scaling_max_freq_oc" -gt "1000000" ]; then
				WAKE_MAX_FREQ="$scaling_max_freq_oc";
			else
				WAKE_MAX_FREQ="$scaling_max_freq";
			fi;
			echo "$scaling_min_freq" > "$min_freq_limit_0_tmp";
			echo "$scaling_min_freq" > "$min_freq_limit_1_tmp";
			echo "$scaling_min_freq" > /sys/devices/system/cpu/cpu0/cpufreq/scaling_min_freq;
			echo "$WAKE_MAX_FREQ" > "$max_freq_limit_0_tmp";
			echo "$WAKE_MAX_FREQ" > "$max_freq_limit_1_tmp";
			echo "$WAKE_MAX_FREQ" > /sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq;
		fi;

		log -p i -t "$FILE_NAME" "*** CENTRAL_CPU_FREQ: $state ***: done";
	else
		log -p i -t "$FILE_NAME" "*** CENTRAL_CPU_FREQ: NOT CHANGED ***: done";
	fi;
}

# boost CPU power for fast and no lag wakeup
MEGA_BOOST_CPU_TWEAKS()
{
	if [ "$cortexbrain_cpu" == "on" ]; then
		CENTRAL_CPU_FREQ "wake_boost";

		log -p i -t "$FILE_NAME" "*** MEGA_BOOST_CPU_TWEAKS ***";
	else
		echo "$scaling_max_freq" > /sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq;
	fi;
}

BOOST_DELAY()
{
	# check if ROM booting now, then don't wait - creation and deletion of $DATA_DIR/booting @> /sbin/ext/post-init.sh
	if [ "$wakeup_boost" -gt "0" ] && [ ! -e "$DATA_DIR"/booting ]; then
		log -p i -t "$FILE_NAME" "*** BOOST_DELAY: ${wakeup_boost}sec ***";
		sleep "$wakeup_boost";
	fi;
}

# set swappiness in case that no root installed, and zram used or disk swap used
SWAPPINESS()
{
	local SWAP_CHECK=$(free | grep Swap | awk '{print $2}');

	if [ "$SWAP_CHECK" -eq "0" ]; then
		echo "0" > /proc/sys/vm/swappiness;
	else
		echo "$swappiness" > /proc/sys/vm/swappiness;
	fi;

	log -p i -t "$FILE_NAME" "*** SWAPPINESS: $swappiness ***";
}
apply_cpu="$2";
if [ "$apply_cpu" != "update" ]; then
	SWAPPINESS;
fi;

# disable/enable ipv6
IPV6()
{
	local state='';

	if [ -e /data/data/com.cisco.anyconnec* ]; then
		local CISCO_VPN=1;
	else
		local CISCO_VPN=0;
	fi;

	if [ "$cortexbrain_ipv6" == "on" ] || [ "$CISCO_VPN" -eq "1" ]; then
		echo "0" > /proc/sys/net/ipv6/conf/wlan0/disable_ipv6;
		sysctl -w net.ipv6.conf.all.disable_ipv6=0 > /dev/null;
		local state="enabled";
	else
		echo "1" > /proc/sys/net/ipv6/conf/wlan0/disable_ipv6;
		sysctl -w net.ipv6.conf.all.disable_ipv6=1 > /dev/null;
		local state="disabled";
	fi;

	log -p i -t "$FILE_NAME" "*** IPV6 ***: $state";
}

NET()
{
	local state="$1";

	if [ "$state" == "awake" ]; then
		echo "3" > /proc/sys/net/ipv4/tcp_keepalive_probes; # default: 3
		echo "1200" > /proc/sys/net/ipv4/tcp_keepalive_time; # default: 7200s
		echo "10" > /proc/sys/net/ipv4/tcp_keepalive_intvl; # default: 75s
		echo "10" > /proc/sys/net/ipv4/tcp_retries2; # default: 15
	elif [ "$state" == "sleep" ]; then
		echo "2" > /proc/sys/net/ipv4/tcp_keepalive_probes;
		echo "300" > /proc/sys/net/ipv4/tcp_keepalive_time;
		echo "5" > /proc/sys/net/ipv4/tcp_keepalive_intvl;
		echo "5" > /proc/sys/net/ipv4/tcp_retries2;
	fi;

	log -p i -t "$FILE_NAME" "*** NET ***: $state";
}

#KERNEL_SCHED()
#{
#	local state="$1";
#
#	# this is the correct order to input this settings, every value will be x2 after set
#	if [ "$state" == "awake" ]; then
#		sysctl -w kernel.sched_wakeup_granularity_ns=1000000 > /dev/null 2>&1;
#		sysctl -w kernel.sched_min_granularity_ns=750000 > /dev/null 2>&1;
#		sysctl -w kernel.sched_latency_ns=6000000 > /dev/null 2>&1;
#	elif [ "$state" == "sleep" ]; then
#		sysctl -w kernel.sched_wakeup_granularity_ns=1000000 > /dev/null 2>&1;
#		sysctl -w kernel.sched_min_granularity_ns=750000 > /dev/null 2>&1;
#		sysctl -w kernel.sched_latency_ns=6000000 > /dev/null 2>&1;
#	fi;
#
#	log -p i -t "$FILE_NAME" "*** KERNEL_SCHED ***: $state";
#}

BLN_CORRECTION()
{
	if [ "$notification_enabled" == "on" ]; then
		echo "1" > /sys/class/misc/notification/notification_enabled;

		if [ "$blnww" == "off" ]; then
			if [ "$bln_switch" -eq "0" ]; then
				/res/uci.sh bln_switch 0;
			elif [ "$bln_switch" -eq "1" ]; then
				/res/uci.sh bln_switch 1;
			elif [ "$bln_switch" -eq "2" ]; then
				/res/uci.sh bln_switch 2;
			fi;
		else
			/res/uci.sh bln_switch 0 > /dev/null;
			/res/uci.sh generic /sys/class/misc/notification/notification_timeout 0 > /dev/null;
		fi;

		if [ "$dyn_brightness" == "on" ]; then
			echo "0" > /sys/class/misc/notification/dyn_brightness;
		fi;

		log -p i -t "$FILE_NAME" "*** BLN_CORRECTION ***";

		return 1;
	else
		return 0;
	fi;
}

TOUCH_KEYS_CORRECTION()
{
	if [ "$force_disable" -eq "0" ]; then
		if [ "$dyn_brightness" == "on" ]; then
			echo "1" > /sys/class/misc/notification/dyn_brightness;
		fi;

		/res/uci.sh generic /sys/class/misc/notification/led_timeout_ms "$led_timeout_ms" > /dev/null;

		log -p i -t "$FILE_NAME" "*** TOUCH_KEYS_CORRECTION: $dyn_brightness - ${led_timeout_ms}ms ***";
	else
		echo "1" > /sys/devices/virtual/sec/sec_touchkey/force_disable;
		log -p i -t "$FILE_NAME" "*** TOUCH_KEYS_CORRECTION: LEDS are forced OFF ***";
	fi;
}

# if crond used, then give it root perent - if started by STweaks, then it will be killed in time
CROND_SAFETY()
{
	if [ "$crontab" == "on" ]; then
		pkill -f "crond";
		/res/crontab_service/service.sh;

		log -p i -t "$FILE_NAME" "*** CROND_SAFETY ***";

		return 1;
	else
		return 0;
	fi;
}

GAMMA_FIX()
{
	local min_gamm_tmp="/sys/class/misc/brightness_curve/min_gamma";
	if [ -e "$min_gamm_tmp" ]; then
		min_gamm_tmp="/dev/null";
	fi;

	local max_gamma_tmp="/sys/class/misc/brightness_curve/max_gamma";
	if [ -e "$max_gamma_tmp" ]; then
		max_gamma_tmp="/dev/null";
	fi;

	echo "$min_gamma" > "$min_gamm_tmp";
	echo "$max_gamma" > "$max_gamma_tmp";

	log -p i -t "$FILE_NAME" "*** GAMMA_FIX: min: $min_gamma max: $max_gamma ***: done";
}

ENABLEMASK()
{
	local state="$1";
	local enable_mask_tmp="/sys/module/cpuidle_exynos4/parameters/enable_mask";
	if [ -e "$enable_mask_tmp" ]; then
		enable_mask_tmp="/dev/null";
	fi;

	local tmp_enable_mask=$(cat "$enable_mask_tmp");

	if [ "$state" == "awake" ]; then
		if [ "$tmp_enable_mask" != "$enable_mask" ]; then
			echo "$enable_mask" > "$enable_mask_tmp";
		fi;
	elif [ "$state" == "sleep" ]; then
		if [ "$tmp_enable_mask" != "$enable_mask_sleep" ]; then
			echo "$enable_mask_sleep" > "$enable_mask_tmp";
		fi;
	fi;

	log -p i -t "$FILE_NAME" "*** ENABLEMASK: $state ***: done";
}

IO_SCHEDULER()
{
	if [ "$cortexbrain_io" == "on" ]; then

		local state="$1";
		local sys_mmc0_scheduler_tmp="/sys/block/mmcblk0/queue/scheduler";
		local sys_mmc1_scheduler_tmp="/sys/block/mmcblk1/queue/scheduler";
		local new_scheduler="";
		local tmp_scheduler=$(cat "$sys_mmc0_scheduler_tmp" | sed -n 's/^.*\[\([a-z|A-Z]*\)\].*/\1/p');

		if [ ! -e "$sys_mmc1_scheduler_tmp" ]; then
			sys_mmc1_scheduler_tmp="/dev/null";
		fi;

		local ext_tmp_scheduler=$(cat "$sys_mmc1_scheduler_tmp" | sed -n 's/^.*\[\([a-z|A-Z]*\)\].*/\1/p');

		if [ "$state" == "awake" ]; then
			new_scheduler="$scheduler";
			if [ "$tmp_scheduler" != "$scheduler" ]; then
				echo "$scheduler" > "$sys_mmc0_scheduler_tmp";
			fi;
			if [ "$ext_tmp_scheduler" != "deadline" ]; then
				echo "deadline" > "$sys_mmc1_scheduler_tmp";
			fi;
		elif [ "$state" == "sleep" ]; then
			new_scheduler="$sleep_scheduler";
			if [ "$tmp_scheduler" != "$sleep_scheduler" ]; then
				echo "$sleep_scheduler" > "$sys_mmc0_scheduler_tmp";
			fi;
			if [ "$ext_tmp_scheduler" != "$sleep_scheduler" ]; then
				echo "$sleep_scheduler" > "$sys_mmc1_scheduler_tmp";
			fi;
		fi;

		log -p i -t "$FILE_NAME" "*** IO_SCHEDULER: $state - $new_scheduler ***: done";
	else
		log -p i -t "$FILE_NAME" "*** Cortex IO_SCHEDULER: Disabled ***";
	fi;
}

CPU_GOVERNOR()
{
	local state="$1";
	local scaling_governor_tmp="/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor";
	local tmp_governor=$(cat $scaling_governor_tmp);

	if [ "$cortexbrain_cpu" == "on" ]; then
		if [ "$state" == "awake" ]; then
			if [ "$tmp_governor" != "$scaling_governor" ]; then
				echo "$scaling_governor" > "$scaling_governor_tmp";
			fi;
		elif [ "$state" == "sleep" ]; then
			if [ "$tmp_governor" != "$scaling_governor_sleep" ]; then
				echo "$scaling_governor_sleep" > "$scaling_governor_tmp";
			fi;
		fi;

		local USED_GOV_NOW=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor);

		log -p i -t "$FILE_NAME" "*** CPU_GOVERNOR: set $state GOV $USED_GOV_NOW ***: done";
	else
		log -p i -t "$FILE_NAME" "*** CPU_GOVERNOR: NO CHANGED ***: done";
	fi;
}

SLIDE2WAKE_FIX()
{
	local state="$1";
	local SLIDE_STATE=0;
	local tsp_slide2wake_call_tmp="/sys/devices/virtual/sec/sec_touchscreen/tsp_slide2wake_call";

	if [ -e "$tsp_slide2wake_call_tmp" ]; then
		SLIDE_STATE=$(cat "$tsp_slide2wake_call_tmp");
	fi;

	if [ "$tsp_slide2wake" == "on" ]; then
		if [ "$state" == "offline" ] && [ "$SLIDE_STATE" -eq "1" ]; then
			echo "0" > "$tsp_slide2wake_call_tmp";
			log -p i -t "$FILE_NAME" "*** SLIDE2WAKE_FIX: $state ***: done";
		elif [ "$state" == "oncall" ]; then
			echo "1" > "$tsp_slide2wake_call_tmp";
			log -p i -t "$FILE_NAME" "*** SLIDE2WAKE_FIX: $state ***: done";
		fi;
	fi;
}

CALL_STATE()
{
	if [ "$DUMPSYS_STATE" -eq "1" ]; then

		# check the call state, not on call = 0, on call = 2
		local state_tmp=$(echo "$TELE_DATA" | awk '/mCallState/ {print $1}');

		if [ "$state_tmp" != "mCallState=0" ]; then
			NOW_CALL_STATE=1;
		else
			NOW_CALL_STATE=0;
		fi;

		log -p i -t "$FILE_NAME" "*** CALL_STATE: $NOW_CALL_STATE ***";
	else
		NOW_CALL_STATE=0;
	fi;
}

VIBRATE_FIX()
{
	echo "$pwm_value" > /sys/class/timed_output/vibrator/pwm_value;

	log -p i -t "$FILE_NAME" "*** VIBRATE_FIX: $pwm_value ***";
}

MOUNT_FIX()
{
	local CHECK_SYSTEM=$(mount | grep "/system" | grep rw | wc -l);
	local CHECK_DATA=$(mount | grep "/data" | cut -c 26-27 | grep ro | grep -v ec | grep -v ec | wc -l);
	local PRELOAD_CHECK=$(mount | grep "/preload" | grep ro | wc -l);
	local SDCARD_CHECK=$(mount | grep "/storage/sdcard0" | grep rw | grep -v tmpfs | wc -l);

	if [ "$SDCARD_CHECK" -eq "0" ]; then
		mount -o remount,rw /storage/sdcard0;
		log -p i -t "$FILE_NAME" "*** SDCARD_RO_FIX ***";
	fi;
	if [ "$EXTERNAL_SDCARD_CM" -eq "1" ]; then
		local EXT_SDCARD_CHECK=$(mount | grep "/storage/sdcard1" | grep rw | wc -l);
		if [ "$EXT_SDCARD_CHECK" -eq "0" ]; then
			mount -o remount,rw /storage/sdcard1;
			log -p i -t "$FILE_NAME" "*** EXT_SDCARD_RO_FIX ***";
		fi;
	elif [ "$EXTERNAL_SDCARD_STOCK" -eq "1" ]; then
		local EXT_SDCARD_CHECK=$(mount | grep "/storage/extSdCard" | grep rw | wc -l);
		if [ "$EXT_SDCARD_CHECK" -eq "0" ]; then
			mount -o remount,rw /storage/extSdCard;
			log -p i -t "$FILE_NAME" "*** EXT_SDCARD_RO_FIX ***";
		fi;
	fi;
	if [ "$CHECK_SYSTEM" -eq "0" ]; then
		mount -o remount,rw /system;
		log -p i -t "$FILE_NAME" "*** SYSTEM_RO_FIX ***";
	fi;
	if [ "$CHECK_DATA" -eq "1" ]; then
		mount -o remount,rw /data;
		log -p i -t "$FILE_NAME" "*** DATA_RO_FIX ***";
	fi;
	if [ "$PRELOAD_CHECK" -eq "1" ]; then
		mount -o remount,rw /preload;
		log -p i -t "$FILE_NAME" "*** PRELOAD_RO_FIX ***";
	fi;
}

# ==============================================================
# TWEAKS: if Screen-ON
# ==============================================================
AWAKE_MODE()
{
	# Do not touch this
	CALL_STATE;
	VIBRATE_FIX;
	SLIDE2WAKE_FIX "offline";
	GAMMA_FIX;

	# Check call state, if on call dont sleep
	if [ "$NOW_CALL_STATE" -eq "1" ]; then
		CENTRAL_CPU_FREQ "awake_normal";
		NOW_CALL_STATE=0;
	else
		# not on call, check if was powerd by USB on sleep, or didnt sleep at all
		if [ "$WAS_IN_SLEEP_MODE" -eq "1" ] && [ "$USB_POWER" -eq "0" ]; then
			ENABLEMASK "awake";
			CPU_GOVERNOR "awake";
			CPU_GOV_TWEAKS "awake";
			TWEAK_HOTPLUG_ECO "awake";
			MEGA_BOOST_CPU_TWEAKS;
			LOGGER "awake";
			MALI_TIMEOUT "wake_boost";
			BUS_THRESHOLD "wake_boost";
#			KERNEL_SCHED "awake";
			NET "awake";
			MOBILE_DATA "awake";
			WIFI "awake";
			IO_SCHEDULER "awake";
			GESTURES "awake";
			MOUNT_SD_CARD;

			BOOST_DELAY;

			CENTRAL_CPU_FREQ "awake_normal";
			MALI_TIMEOUT "awake";
			BUS_THRESHOLD "awake";
			ECO_TWEAKS;
			MOUNT_FIX;
			TOUCH_KEYS_CORRECTION;
		else
			# Was powered by USB, and half sleep
			ENABLEMASK "awake";
			MEGA_BOOST_CPU_TWEAKS;
			MALI_TIMEOUT "wake_boost";
			GESTURES "awake";

			BOOST_DELAY;

			MALI_TIMEOUT "awake";
			CENTRAL_CPU_FREQ "awake_normal";
			ECO_TWEAKS;
			MOUNT_FIX;
			TOUCH_KEYS_CORRECTION;
			USB_POWER=0;

			log -p i -t "$FILE_NAME" "*** USB_POWER_WAKE: done ***";
		fi;
	fi;
}

# ==============================================================
# TWEAKS: if Screen-OFF
# ==============================================================
SLEEP_MODE()
{
	WAS_IN_SLEEP_MODE=0;

	# we only read the config when the screen turns off ...
	PROFILE=$(cat "$DATA_DIR"/.active.profile);
	. "$DATA_DIR"/"$PROFILE".profile;

	# we only read tele-data when the screen turns off ...
	if [ "$DUMPSYS_STATE" -eq "1" ]; then
		TELE_DATA=$(dumpsys telephony.registry);
	fi;

	# Check call state
	CALL_STATE;

	# check if we on call
	if [ "$NOW_CALL_STATE" -eq "0" ]; then
		WAS_IN_SLEEP_MODE=1;
		ENABLEMASK "sleep";
		CENTRAL_CPU_FREQ "standby_freq";
		MALI_TIMEOUT "sleep";
		GESTURES "sleep";
		BLN_CORRECTION;
		CROND_SAFETY;
		SWAPPINESS;

		# for devs use, if debug is on, then finish full sleep with usb connected
		if [ "$android_logger" == "debug" ]; then
			CHARGING=0;
		else
			CHARGING=$(cat /sys/class/power_supply/battery/charging_source);
		fi;

		# check if we powered by USB, if not sleep
		if [ "$CHARGING" -eq "0" ]; then
			CPU_GOVERNOR "sleep";
			CENTRAL_CPU_FREQ "sleep_freq";
			CPU_GOV_TWEAKS "sleep";
			IO_SCHEDULER "sleep";
			BUS_THRESHOLD "sleep";
#			KERNEL_SCHED "sleep";
			NET "sleep";
			WIFI "sleep";
			BATTERY_TWEAKS;
			MOBILE_DATA "sleep";
			IPV6;
			TWEAK_HOTPLUG_ECO "sleep";

			log -p i -t "$FILE_NAME" "*** SLEEP mode ***";

			LOGGER "sleep";
		else
			# Powered by USB
			USB_POWER=1;
			log -p i -t "$FILE_NAME" "*** SLEEP mode: USB CABLE CONNECTED! No real sleep mode! ***";
		fi;
	else
		# Check if on call
		if [ "$NOW_CALL_STATE" -eq "1" ]; then
			CENTRAL_CPU_FREQ "sleep_call";
			SLIDE2WAKE_FIX "oncall";
			NOW_CALL_STATE=1;

			log -p i -t "$FILE_NAME" "*** on call: SLEEP aborted! ***";
		else
			# Early Wakeup detected
			log -p i -t "$FILE_NAME" "*** early wake up: SLEEP aborted! ***";
		fi;
	fi;
}

# ==============================================================
# Background process to check screen state
# ==============================================================

# Dynamic value do not change/delete
cortexbrain_background_process=1;

if [ "$cortexbrain_background_process" -eq "1" ] && [ "$(pgrep -f "/sbin/ext/cortexbrain-tune.sh" | wc -l)" -eq "2" ]; then
	(while true; do
		while [ "$(cat /proc/sys/vm/vfs_cache_pressure)" != "60" ]; do
			sleep "2";
		done;
		# AWAKE State. all system ON
		AWAKE_MODE;

		while [ "$(cat /proc/sys/vm/vfs_cache_pressure)" != "20" ]; do
			sleep "2";
		done;
		# SLEEP state. All system to power save
		SLEEP_MODE;
	done &);
else
	if [ "$cortexbrain_background_process" -eq "0" ]; then
		echo "Cortex background disabled!"
	else
		echo "Cortex background process already running!";
	fi;
fi;

# ==============================================================
# Logic Explanations
#
# This script will manipulate all the system / cpu / battery behavior
# Based on chosen STWEAKS profile+tweaks and based on SCREEN ON/OFF state.
#
# When User select battery/default profile all tuning will be toward battery save.
# But user loose performance -20% and get more stable system and more battery left.
#
# When user select performance profile, tuning will be to max performance on screen ON.
# When screen OFF all tuning switched to max power saving. as with battery profile,
# So user gets max performance and max battery save but only on screen OFF.
#
# This script change governors and tuning for them on the fly.
# Also switch on/off hotplug CPU core based on screen on/off.
# This script reset battery stats when battery is 100% charged.
# This script tune Network and System VM settings and ROM settings tuning.
# This script changing default MOUNT options and I/O tweaks for all flash disks and ZRAM.
#
# TODO: add more description, explanations & default vaules ...
#
