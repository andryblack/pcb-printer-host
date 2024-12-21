#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include "become_daemon.h"

#define BD_MAX_CLOSE       8192 /* Max file descriptors to close if
                                   sysconf(_SC_OPEN_MAX) is indeterminate */


int // returns 0 on success -1 on error
become_daemon()
{
  
  /* The first fork will change our pid
   * but the sid and pgid will be the
   * calling process.
   */
  switch(fork())                    // become background process
  {
    case -1: return -1;
    case 0: break;                  // child falls through
    default: _exit(EXIT_SUCCESS);   // parent terminates
  }

  /*
   * Run the process in a new session without a controlling
   * terminal. The process group ID will be the process ID
   * and thus, the process will be the process group leader.
   * After this call the process will be in a new session,
   * and it will be the progress group leader in a new
   * process group.
   */
  if(setsid() == -1)                // become leader of new session
    return -1;

  /*
   * We will fork again, also known as a
   * double fork. This second fork will orphan
   * our process because the parent will exit.
   * When the parent process exits the child
   * process will be adopted by the init process
   * with process ID 1.
   * The result of this second fork is a process
   * with the parent as the init process with an ID
   * of 1. The process will be in it's own session
   * and process group and will have no controlling
   * terminal. Furthermore, the process will not
   * be the process group leader and thus, cannot
   * have the controlling terminal if there was one.
   */
  switch(fork())
  {
    case -1: return -1;
    case 0: break;                  // child breaks out of case
    default: _exit(EXIT_SUCCESS);   // parent process will exit
  }

  // if(!(flags & BD_NO_UMASK0))
  //   umask(0);                       // clear file creation mode mask

  // if(!(flags & BD_NO_CHDIR))
  //   chdir("/");                     // change to root directory

  if(true)  // close all open files
  {
    int maxfd = sysconf(_SC_OPEN_MAX);
    if(maxfd == -1)
      maxfd = BD_MAX_CLOSE;         // if we don't know then guess
    for(int fd = 0; fd < maxfd; fd++)
      close(fd);
  }

  return 0;
}

int redirect_log(const char* logfile) {
  close(STDIN_FILENO);

  int fdnull = open("/dev/null", O_RDWR);
  if(fdnull != STDIN_FILENO)
      return -1;

  int fdout = fdnull;
  if (logfile) {
    fdout = open(logfile,O_CREAT|O_WRONLY|O_TRUNC,0666);
  } 

  if(dup2(fdout, STDOUT_FILENO) != STDOUT_FILENO)
      return -2;
  if(dup2(fdout, STDERR_FILENO) != STDERR_FILENO)
      return -3;

  return 0;
}

int write_pid(const char* pidfile) {
  if (!pidfile) return 0;
  int fd = open(pidfile,O_CREAT|O_WRONLY|O_TRUNC,0666);
  if (fd<0) {
    return fd;
  }
  auto p = getpid();
  char buf[32];
  snprintf(buf,32,"%d",p);
  write(fd,buf,strlen(buf));
  close(fd);
  return 0;
}