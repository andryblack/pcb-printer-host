string {
	name = 'device',
	descr = 'serial connection device',
	default = 'fake',
	page = 'connection'
}

integer {
	name = 'baudrate',
	control = 'select',
	descr = 'serial connection baudrate',
	values = {
		115200,
		230400
	},
	default = 115200,
	page = 'connection'
}

number {
	name = 'printer_width',
	descr = 'Printer move X (mm)',
	default = 200,
	page = 'printer'
}

number {
	name = 'printer_height',
	descr = 'Printer move Y (mm)',
	default = 200,
	page = 'printer'
}

number {
	name = 'printer_encoder_resolution',
	descr = 'Printer encoder resolution (lpi)',
	default = 180,
	page = 'printer'
}

number {
	name = 'motor_pid_P',
	descr = 'Motor PID P parameter',
	default = 0.05,
	page = 'printer'
}

number {
	name = 'motor_pid_I',
	descr = 'Motor PID I parameter',
	default = 0.0005,
	page = 'printer'
}

number {
	name = 'motor_pid_D',
	descr = 'Motor PID D parameter',
	default = 0.00005,
	page = 'printer'
}

number {
	name = 'motor_min_speed',
	descr = 'Min X motor speed (mm/s)',
	default = 10,
	page = 'printer'
}

number {
	name = 'motor_max_speed',
	descr = 'Max X motor speed (mm/s)',
	default = 1000,
	page = 'printer'
}

number {
	name = 'printer_y_steps',
	descr = 'Steps per mm',
	default = 200,
	page = 'printer'
}

number {
	name = 'printer_y_min_speed',
	descr = 'Y min mm / s',
	default = 0.1,
	page = 'printer'
}

number {
	name = 'printer_y_max_speed',
	descr = 'Y max mm / s',
	default = 1.0,
	page = 'printer'
}

number {
	name = 'printer_y_accel',
	descr = 'Y acceleration mm / s2',
	default = 1.0,
	page = 'printer'
}

number {
	name = 'printer_y_deccel',
	descr = 'Y decceleration mm / s2',
	default = 1.0,
	page = 'printer'
}

number {
	name = 'printer_y_stop_steps',
	descr = 'Y stop mm',
	default = 0.5,
	page = 'printer'
}

number {
	name = 'print_speed',
	descr = 'X speed mm / s',
	default = 500,
	page = 'printer'
}

number {
	name = 'flash_time',
	descr = 'Laser flash time ms',
	default = 50,
	page = 'printer'
}



boolean {
	name = 'pcb_negative',
	descr = 'Default drawing negative',
	default = false,
	page = 'pcb'
}

number {
	name = 'pcb_drill_kern_r',
	descr = 'Drill kerning r(mm)',
	default = 0.2,
	page = 'pcb'
}

number {
	name = 'pcb_drill_kern_or',
	descr = 'Drill kerning outline r(mm)',
	default = 0.5,
	page = 'pcb'
}

string {
	name = 'camera_url',
	descr = 'Camera steam url',
	page = 'camera',
}

integer {
	name = 'camera_port',
	descr = 'Camera steam port',
	page = 'camera',
	default = 8081
}

string {
	name = 'camera_device',
	descr = 'Camera device',
	page = 'camera',
	default = '/dev/video0'
}

integer {
	name = 'camera_size_x',
	descr = 'Camera resolution X',
	page = 'camera',
	default = 640
}

integer {
	name = 'camera_size_y',
	descr = 'Camera resolution Y',
	page = 'camera',
	default = 480
}

integer {
	name = 'camera_pos_x',
	descr = 'Camera crosshair X',
	page = 'camera',
	default = 320
}

integer {
	name = 'camera_pos_y',
	descr = 'Camera crosshair Y',
	page = 'camera',
	default = 240
}

boolean {
	name = 'camera_flip_x',
	descr = 'Flip image X',
	default = false,
	page = 'camera'
}

boolean {
	name = 'camera_flip_y',
	descr = 'Flip image Y',
	default = false,
	page = 'camera'
}
