/* FreeTDS - Library of routines accessing Sybase and Microsoft databases
 * Copyright (C) 1998-2011  Brian Bruns
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public
 * License as published by the Free Software Foundation; either
 * version 2 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Library General Public License for more details.
 *
 * You should have received a copy of the GNU Library General Public
 * License along with this library; if not, write to the
 * Free Software Foundation, Inc., 59 Temple Place - Suite 330,
 * Boston, MA 02111-1307, USA.
 */

#ifndef _tds_sysdep_public_h_
#define _tds_sysdep_public_h_

/*
 * This file is publicly installed.
 * MUST not include config.h
 */

#if (!defined(_MSC_VER) && defined(__cplusplus) && __cplusplus >= 201103L) || \
	(defined(_MSC_VER) && _MSC_VER >= 1600) || \
	(defined(__STDC_VERSION__) && __STDC_VERSION__ >= 199901L)
#  include <stdint.h>
#elif (defined(__sun) && defined(__SVR4)) || defined(__hpux)
#  include <inttypes.h>
#else
typedef   signed char      int8_t;	/* 8-bit int */
typedef unsigned char     uint8_t;	/* 8-bit int */
/*
 * This is where platform-specific changes need to be made.
 */
#  if defined(WIN32) || defined(_WIN32) || defined(__WIN32__)
#    include <winsock2.h>
#    include <ws2tcpip.h>
#    include <windows.h>
  typedef   signed short    int16_t;	/* 16-bit int */
  typedef unsigned short   uint16_t;	/* 16-bit int */
  typedef   signed int      int32_t;	/* 32-bit int */
  typedef unsigned int     uint32_t;	/* 32-bit int */
  typedef   signed __int64  int64_t;	/* 64-bit int */
  typedef unsigned __int64 uint64_t;	/* 64-bit int */
#  else				/* defined(WIN32) || defined(_WIN32) || defined(__WIN32__) */
  typedef   signed  short   int16_t;	/* 16-bit int */
  typedef unsigned  short  uint16_t;	/* 16-bit int */
  typedef   signed  int   int32_t;	/* 32-bit int */
  typedef unsigned  int  uint32_t;	/* 32-bit int */
  typedef   signed  long   int64_t;	/* 64-bit int */
  typedef unsigned  long  uint64_t;	/* 64-bit int */
#  endif
#endif

#include <float.h>

/* try to understand float sizes using float.h constants */
#if FLT_RADIX == 2
#  if FLT_MANT_DIG == 24 && FLT_MAX_EXP == 128
#    define tds_sysdep_real32_type float	/* 32-bit real */
#  elif DBL_MANT_DIG == 24 && DBL_MAX_EXP == 128
#    define tds_sysdep_real32_type double	/* 32-bit real */
#  elif LDBL_MANT_DIG == 24 && LDBL_MAX_EXP == 128
#    define tds_sysdep_real32_type long double	/* 32-bit real */
#  endif
#  if FLT_MANT_DIG == 53 && FLT_MAX_EXP == 1024
#    define tds_sysdep_real64_type float	/* 64-bit real */
#  elif DBL_MANT_DIG == 53 && DBL_MAX_EXP == 1024
#    define tds_sysdep_real64_type double	/* 64-bit real */
#  elif LDBL_MANT_DIG == 53 && LDBL_MAX_EXP == 1024
#    define tds_sysdep_real64_type long double	/* 64-bit real */
#  endif
#  if !defined(tds_sysdep_real32_type) || !defined(tds_sysdep_real64_type)
#    error Some float type was not found!
#  endif
#else
#  if FLT_DIG == 6 && FLT_MAX_10_EXP == 38
#    define tds_sysdep_real32_type float	/* 32-bit real */
#  elif DBL_DIG == 6 && DBL_MAX_10_EXP == 38
#    define tds_sysdep_real32_type double	/* 32-bit real */
#  elif LDBL_DIG == 6 && LDBL_MAX_10_EXP == 38
#    define tds_sysdep_real32_type long double	/* 32-bit real */
#  endif
#  if FLT_DIG == 15 && FLT_MAX_10_EXP == 308
#    define tds_sysdep_real64_type float	/* 64-bit real */
#  elif DBL_DIG == 15 && DBL_MAX_10_EXP == 308
#    define tds_sysdep_real64_type double	/* 64-bit real */
#  elif LDBL_DIG == 15 && LDBL_MAX_10_EXP == 308
#    define tds_sysdep_real64_type long double	/* 64-bit real */
#  endif
#endif

/* fall back to configure.ac types */
#ifndef tds_sysdep_real32_type
#define tds_sysdep_real32_type float	/* 32-bit real */
#endif				/* !tds_sysdep_real32_type */

#ifndef tds_sysdep_real64_type
#define tds_sysdep_real64_type double	/* 64-bit real */
#endif				/* !tds_sysdep_real64_type */

#if !defined(MSDBLIB) && !defined(SYBDBLIB)
#define SYBDBLIB 1
#endif
#if defined(MSDBLIB) && defined(SYBDBLIB)
#error MSDBLIB and SYBDBLIB cannot both be defined
#endif

#endif				/* _tds_sysdep_public_h_ */
