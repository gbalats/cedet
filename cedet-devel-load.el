;;; cedet-devel-load.el --- Use CEDET from SourceForge, not Emacs

;; Copyright (C) 2011 by Eric M. Ludlam

;; This file is not part of Emacs, and will STAY a part of CEDET/Standalone

;; This program is free software; you can redistribute it and/or
;; modify it under the terms of the GNU General Public License as
;; published by the Free Software Foundation; either version 2, or (at
;; your option) any later version.

;; This program is distributed in the hope that it will be useful, but
;; WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
;; General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program; see the file COPYING.  If not, write to
;; the Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
;; Boston, MA 02110-1301, USA.

;;; Commentary:
;;
;; This file is for using the CEDET from the CEDET standalone bzr
;; repository, replacing the version that comes with Emacs 23.x and greater.

;;; Code:
(when (featurep 'cedet-devel-load)
  (error "CEDET Version %s already loaded." cedet-version))

;; This file must be in "<INSTALL-DIR>" where 'cedet.el' that
;; comes with the associated repository is in: "<INSTALL-DIR>/lisp/cedet/cedet.el".
(let ((CEDETDIR (file-name-directory
		 (or load-file-name (buffer-file-name)))))

  ;; SETUP LOAD PATHS
  (add-to-list 'load-path CEDETDIR)
  (add-to-list 'load-path (expand-file-name "lisp/cedet" CEDETDIR))
  (add-to-list 'load-path (expand-file-name "lisp/eieio" CEDETDIR))
  (add-to-list 'load-path (expand-file-name "lisp/common" CEDETDIR))
  (add-to-list 'load-path (expand-file-name "lisp/speedbar" CEDETDIR))

  (require 'eieio)
  (require 'ede)

  ;; Load in all the loaddefs
  (load-file (expand-file-name "lisp/eieio/loaddefs.el" CEDETDIR))
  (load-file (expand-file-name "lisp/speedbar/loaddefs.el" CEDETDIR))
  (load-file (expand-file-name "lisp/cedet/ede/loaddefs.el" CEDETDIR))
  (load-file (expand-file-name "lisp/cedet/cogre/loaddefs.el" CEDETDIR))
  (load-file (expand-file-name "lisp/cedet/srecode/loaddefs.el" CEDETDIR))
  (load-file (expand-file-name "lisp/cedet/semantic/loaddefs.el"CEDETDIR))
  (load-file (expand-file-name "lisp/cedet/semantic/bovine/loaddefs.el" CEDETDIR))
  (load-file (expand-file-name "lisp/cedet/semantic/wisent/loaddefs.el" CEDETDIR))
  (load-file (expand-file-name "lisp/cedet/semantic/analyze/loaddefs.el" CEDETDIR))
  (load-file (expand-file-name "lisp/cedet/semantic/decorate/loaddefs.el" CEDETDIR))
  (load-file (expand-file-name "lisp/cedet/semantic/ectags/loaddefs.el" CEDETDIR))


  ;; SETUP INFO DIRS
  ;; @TODO
  
  )



(require 'cedet) ;; Get standard CEDET variables loaded.

;; Load in COMPAT code - This is because NEW CEDET code may use this
;; for compatibility reasons, but Emacs integrated code removes it.
(require 'cedet-compat)

;; Add some autoloads by hand due to:
;;  New code
;;  Things disabled by core Emacs
;;
;;  @TODO - generate autoloads.
(autoload 'semantic-default-elisp-setup "semantic/bovine/el"
  "Setup hook function for Emacs Lisp files and Semantic.")

;; Get SRecode initialized
(require 'srecode)
(require 'srecode/map) ;; Get the srecode load-path filled in.

(let ((CEDETDIR (file-name-directory
		 (or load-file-name (buffer-file-name)))))
  (add-to-list 'srecode-map-load-path (expand-file-name "etc/srecode" CEDETDIR))

  )

(provide 'cedet-devel-load)

;; End
