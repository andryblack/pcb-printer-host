#pragma once

int become_daemon();
int redirect_log(const char* logfile);
int write_pid(const char* pidfile);

