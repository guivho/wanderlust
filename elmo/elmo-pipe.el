;;; elmo-pipe.el --- PIPE Interface for ELMO.

;; Copyright (C) 1998,1999,2000 Yuuichi Teranishi <teranisi@gohome.org>

;; Author: Yuuichi Teranishi <teranisi@gohome.org>
;; Keywords: mail, net news

;; This file is part of ELMO (Elisp Library for Message Orchestration).

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 2, or (at your option)
;; any later version.
;;
;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to the
;; Free Software Foundation, Inc., 59 Temple Place - Suite 330,
;; Boston, MA 02111-1307, USA.
;;

;;; Commentary:
;;

;;; Code:
;;

(require 'elmo)

(defvar elmo-pipe-folder-copied-filename "copied"
  "Copied messages number set.")

;;; ELMO pipe folder
(eval-and-compile
  (luna-define-class elmo-pipe-folder (elmo-folder)
		     (src dst copy))
  (luna-define-internal-accessors 'elmo-pipe-folder))

(luna-define-method elmo-folder-initialize ((folder elmo-pipe-folder)
					    name)
  (when (string-match "^\\([^|]*\\)|\\(:?\\)\\(.*\\)$" name)
    (elmo-pipe-folder-set-src-internal folder
				       (elmo-make-folder
					(elmo-match-string 1 name)))
    (elmo-pipe-folder-set-dst-internal folder
				       (elmo-make-folder
					(elmo-match-string 3 name)))
    (elmo-pipe-folder-set-copy-internal folder
					(string= ":"
						 (elmo-match-string 2 name))))
  folder)

(luna-define-method elmo-folder-get-primitive-list ((folder elmo-pipe-folder))
  (elmo-flatten
   (mapcar
    'elmo-folder-get-primitive-list
    (list (elmo-pipe-folder-src-internal folder)
	  (elmo-pipe-folder-dst-internal folder)))))

(luna-define-method elmo-folder-contains-type ((folder elmo-pipe-folder)
					       type)
  (or (elmo-folder-contains-type (elmo-pipe-folder-src-internal folder) type)
      (elmo-folder-contains-type (elmo-pipe-folder-dst-internal folder) type)))

(luna-define-method elmo-folder-append-messages ((folder elmo-pipe-folder)
						 src-folder numbers
						 &optional same-number)
  (elmo-folder-append-messages (elmo-pipe-folder-dst-internal folder)
			       src-folder numbers
			       same-number))

(luna-define-method elmo-folder-append-buffer ((folder elmo-pipe-folder)
					       &optional flag number)
  (elmo-folder-append-buffer (elmo-pipe-folder-dst-internal folder)
			     flag number))

(luna-define-method elmo-message-fetch ((folder elmo-pipe-folder)
					number strategy
					&optional section outbuf unseen)
  (elmo-message-fetch (elmo-pipe-folder-dst-internal folder)
		      number strategy section outbuf unseen))

(luna-define-method elmo-folder-clear :after ((folder elmo-pipe-folder)
					      &optional keep-killed)
  (unless keep-killed
    (elmo-pipe-folder-copied-list-save folder nil)))

(luna-define-method elmo-folder-delete-messages ((folder elmo-pipe-folder)
						 numbers)
  (elmo-folder-delete-messages (elmo-pipe-folder-dst-internal folder)
			       numbers))

(defvar elmo-pipe-drained-hook nil "A hook called when the pipe is flushed.")

(defsubst elmo-pipe-folder-list-target-messages (src &optional ignore-list)
  (unwind-protect
      (progn
	(elmo-folder-set-killed-list-internal src ignore-list)
	(elmo-folder-list-messages src))
    (elmo-folder-set-killed-list-internal src nil)))

(defun elmo-pipe-drain (src dst &optional copy ignore-list)
  "Move or copy all messages of SRC to DST."
  (let ((elmo-inhibit-number-mapping (and (eq (elmo-folder-type-internal
					       src) 'pop3)
					  (not copy))) ; No need to use UIDL
	msgs len)
    (message "Checking %s..." (elmo-folder-name-internal src))
    ;; Warnnig: some function requires msgdb
    ;; but elmo-folder-open-internal do not load msgdb.
    (elmo-folder-open-internal src)
    (setq msgs (elmo-pipe-folder-list-target-messages src ignore-list)
	  len (length msgs))
    (when (> len elmo-display-progress-threshold)
      (elmo-progress-set 'elmo-folder-move-messages
			 len
			 (if copy
			     "Copying messages..."
			   "Moving messages...")))
    (unwind-protect
	(elmo-folder-move-messages src msgs dst copy)
      (elmo-progress-clear 'elmo-folder-move-messages))
    (when (and copy msgs)
      (setq ignore-list (elmo-number-set-append-list ignore-list
						     msgs)))
    (elmo-folder-close-internal src)
    (run-hooks 'elmo-pipe-drained-hook)
    ignore-list))

(defun elmo-pipe-folder-copied-list-load (folder)
  (elmo-object-load
   (expand-file-name elmo-pipe-folder-copied-filename
		     (expand-file-name
		      (elmo-replace-string-as-filename
		       (elmo-folder-name-internal folder))
		      (expand-file-name "pipe" elmo-msgdb-directory)))
   nil t))

(defun elmo-pipe-folder-copied-list-save (folder copied-list)
  (elmo-object-save
   (expand-file-name elmo-pipe-folder-copied-filename
		     (expand-file-name
		      (elmo-replace-string-as-filename
		       (elmo-folder-name-internal folder))
		      (expand-file-name "pipe" elmo-msgdb-directory)))
   copied-list))

(luna-define-method elmo-folder-msgdb ((folder elmo-pipe-folder))
  (elmo-folder-msgdb (elmo-pipe-folder-dst-internal folder)))

(luna-define-method elmo-folder-open-internal ((folder elmo-pipe-folder))
  (elmo-folder-open-internal (elmo-pipe-folder-dst-internal folder)))

(luna-define-method elmo-folder-close-internal ((folder elmo-pipe-folder))
  (elmo-folder-close-internal(elmo-pipe-folder-dst-internal folder)))

(luna-define-method elmo-folder-set-message-modified
  ((folder elmo-pipe-folder) modified)
  (elmo-folder-set-message-modified-internal
   (elmo-pipe-folder-dst-internal folder) modified))

(luna-define-method elmo-folder-list-messages ((folder elmo-pipe-folder)
					       &optional visible-only in-msgdb)
  ;; Use target folder's killed-list in the pipe folder.
  (elmo-folder-list-messages (elmo-pipe-folder-dst-internal
			      folder) visible-only in-msgdb))

(luna-define-method elmo-folder-list-unreads ((folder elmo-pipe-folder))
  (elmo-folder-list-unreads (elmo-pipe-folder-dst-internal folder)))

(luna-define-method elmo-folder-list-importants ((folder elmo-pipe-folder))
  (elmo-folder-list-importants (elmo-pipe-folder-dst-internal folder)))

(luna-define-method elmo-folder-list-answereds ((folder elmo-pipe-folder))
  (elmo-folder-list-answereds (elmo-pipe-folder-dst-internal folder)))

(luna-define-method elmo-folder-diff ((folder elmo-pipe-folder))
  (elmo-folder-open-internal (elmo-pipe-folder-src-internal folder))
  (elmo-folder-open-internal (elmo-pipe-folder-dst-internal folder))
  (let* ((elmo-inhibit-number-mapping
	  (not (elmo-pipe-folder-copy-internal folder)))
	 (src-length (length (elmo-pipe-folder-list-target-messages
			      (elmo-pipe-folder-src-internal folder)
			      (elmo-pipe-folder-copied-list-load folder))))
	 (dst-diff (elmo-folder-diff (elmo-pipe-folder-dst-internal folder))))
    (prog1
	(cond
	 ((consp (cdr dst-diff)) ; new unread all
	  (mapcar (lambda (number) (+ number src-length)) dst-diff))
	 (t
	  (cons (+ (car dst-diff) src-length)
		(+ (cdr dst-diff) src-length))))
      ;; No save.
      (elmo-folder-close-internal (elmo-pipe-folder-src-internal folder))
      (elmo-folder-close-internal (elmo-pipe-folder-dst-internal folder)))))

(luna-define-method elmo-folder-exists-p ((folder elmo-pipe-folder))
  (and (elmo-folder-exists-p (elmo-pipe-folder-src-internal folder))
       (elmo-folder-exists-p (elmo-pipe-folder-dst-internal folder))))

(luna-define-method elmo-folder-expand-msgdb-path ((folder
						    elmo-pipe-folder))
  ;; Share with destination...OK?
  (elmo-folder-expand-msgdb-path (elmo-pipe-folder-dst-internal folder)))

(luna-define-method elmo-folder-newsgroups ((folder elmo-pipe-folder))
  (elmo-folder-newsgroups (elmo-pipe-folder-src-internal folder)))

(luna-define-method elmo-folder-creatable-p ((folder elmo-pipe-folder))
  (and (or
	(elmo-folder-exists-p (elmo-pipe-folder-src-internal folder))
	(elmo-folder-creatable-p (elmo-pipe-folder-src-internal folder)))
       (or
	(elmo-folder-exists-p (elmo-pipe-folder-dst-internal folder))
	(elmo-folder-creatable-p (elmo-pipe-folder-dst-internal folder)))))

(luna-define-method elmo-folder-writable-p ((folder elmo-pipe-folder))
  (elmo-folder-writable-p (elmo-pipe-folder-dst-internal folder)))

(luna-define-method elmo-folder-create ((folder elmo-pipe-folder))
  (if (and (not (elmo-folder-exists-p (elmo-pipe-folder-src-internal folder)))
	   (elmo-folder-creatable-p (elmo-pipe-folder-src-internal folder)))
      (elmo-folder-create (elmo-pipe-folder-src-internal folder)))
  (if (and (not (elmo-folder-exists-p (elmo-pipe-folder-dst-internal folder)))
	   (elmo-folder-creatable-p (elmo-pipe-folder-dst-internal folder)))
      (elmo-folder-create (elmo-pipe-folder-dst-internal folder))))

(luna-define-method elmo-folder-search ((folder elmo-pipe-folder)
					condition &optional numlist)
  (elmo-folder-search (elmo-pipe-folder-dst-internal folder)
		      condition numlist))

(luna-define-method elmo-message-use-cache-p ((folder elmo-pipe-folder) number)
  (elmo-message-use-cache-p (elmo-pipe-folder-dst-internal folder) number))

(luna-define-method elmo-folder-check ((folder elmo-pipe-folder))
  (elmo-folder-check (elmo-pipe-folder-dst-internal folder)))

(luna-define-method elmo-folder-plugged-p ((folder elmo-pipe-folder))
  (and (elmo-folder-plugged-p (elmo-pipe-folder-src-internal folder))
       (elmo-folder-plugged-p (elmo-pipe-folder-dst-internal folder))))

(luna-define-method elmo-folder-message-file-p ((folder elmo-pipe-folder))
  (elmo-folder-message-file-p (elmo-pipe-folder-dst-internal folder)))

(luna-define-method elmo-message-file-p ((folder elmo-pipe-folder) number)
  (elmo-message-file-p (elmo-pipe-folder-dst-internal folder) number))

(luna-define-method elmo-message-file-name ((folder elmo-pipe-folder) number)
  (elmo-message-file-name (elmo-pipe-folder-dst-internal folder) number))

(luna-define-method elmo-folder-message-file-number-p ((folder
							elmo-pipe-folder))
  (elmo-folder-message-file-number-p (elmo-pipe-folder-dst-internal folder)))

(luna-define-method elmo-folder-message-file-directory ((folder
							 elmo-pipe-folder))
  (elmo-folder-message-file-directory
   (elmo-pipe-folder-dst-internal folder)))

(luna-define-method elmo-folder-message-make-temp-file-p
  ((folder elmo-pipe-folder))
  (elmo-folder-message-make-temp-file-p
   (elmo-pipe-folder-dst-internal folder)))

(luna-define-method elmo-folder-message-make-temp-files ((folder
							  elmo-pipe-folder)
							 numbers
							 &optional
							 start-number)
  (elmo-folder-message-make-temp-files
   (elmo-pipe-folder-dst-internal folder) numbers start-number))

(luna-define-method elmo-folder-flag-as-read ((folder elmo-pipe-folder)
					      numbers &optional is-local)
  (elmo-folder-flag-as-read (elmo-pipe-folder-dst-internal folder)
			    numbers is-local))

(luna-define-method elmo-folder-unflag-read ((folder elmo-pipe-folder)
					     numbers
					     &optional is-local)
  (elmo-folder-unflag-read (elmo-pipe-folder-dst-internal folder)
			   numbers is-local))

(luna-define-method elmo-folder-unflag-important ((folder elmo-pipe-folder)
						  numbers
						  &optional is-local)
  (elmo-folder-unflag-important (elmo-pipe-folder-dst-internal folder)
				numbers is-local))

(luna-define-method elmo-folder-flag-as-important ((folder elmo-pipe-folder)
						   numbers
						   &optional is-local)
  (elmo-folder-flag-as-important (elmo-pipe-folder-dst-internal folder)
				 numbers is-local))

(luna-define-method elmo-folder-unflag-answered ((folder elmo-pipe-folder)
						 numbers
						 &optional is-local)
  (elmo-folder-unflag-answered (elmo-pipe-folder-dst-internal folder)
			       numbers is-local))

(luna-define-method elmo-folder-flag-as-answered ((folder elmo-pipe-folder)
						  numbers
						  &optional is-local)
  (elmo-folder-flag-as-answered (elmo-pipe-folder-dst-internal folder)
				numbers is-local))

(luna-define-method elmo-folder-pack-numbers ((folder elmo-pipe-folder))
  (elmo-folder-pack-numbers (elmo-pipe-folder-dst-internal folder)))

(luna-define-method elmo-folder-rename ((folder elmo-pipe-folder) new-name)
  (let* ((new-folder (elmo-make-folder new-name)))
    (unless (string= (elmo-folder-name-internal
		      (elmo-pipe-folder-src-internal folder))
		     (elmo-folder-name-internal
		      (elmo-pipe-folder-src-internal new-folder)))
      (error "Source folder differ"))
    (unless (eq (elmo-folder-type-internal
		 (elmo-pipe-folder-dst-internal folder))
		(elmo-folder-type-internal
		 (elmo-pipe-folder-dst-internal new-folder)))
      (error "Not same folder type"))
    (if (or (file-exists-p (elmo-folder-msgdb-path
			    (elmo-pipe-folder-dst-internal new-folder)))
	    (elmo-folder-exists-p
	     (elmo-pipe-folder-dst-internal new-folder)))
	(error "Already exists folder: %s" new-name))
    (elmo-folder-send (elmo-pipe-folder-dst-internal folder)
		      'elmo-folder-rename-internal
		      (elmo-pipe-folder-dst-internal new-folder))
    (elmo-msgdb-rename-path folder new-folder)))

(luna-define-method elmo-folder-synchronize ((folder elmo-pipe-folder)
					     &optional
					     disable-killed
					     ignore-msgdb
					     no-check)
  (let ((src-folder (elmo-pipe-folder-src-internal folder))
	(dst-folder (elmo-pipe-folder-dst-internal folder)))
    (when (and (elmo-folder-plugged-p src-folder)
	       (elmo-folder-plugged-p dst-folder))
      (if (elmo-pipe-folder-copy-internal folder)
	  (elmo-pipe-folder-copied-list-save
	   folder
	   (elmo-pipe-drain src-folder
			    dst-folder
			    'copy
			    (elmo-pipe-folder-copied-list-load folder)))
	(elmo-pipe-drain src-folder dst-folder))))
  (elmo-folder-synchronize
   (elmo-pipe-folder-dst-internal folder)
   disable-killed ignore-msgdb no-check))

(luna-define-method elmo-folder-list-flagged ((folder elmo-pipe-folder)
					      flag
					      &optional in-msgdb)
  (elmo-folder-list-flagged
   (elmo-pipe-folder-dst-internal folder) flag in-msgdb))

(luna-define-method elmo-folder-commit ((folder elmo-pipe-folder))
  (elmo-folder-commit (elmo-pipe-folder-dst-internal folder)))

(luna-define-method elmo-folder-length ((folder elmo-pipe-folder))
  (elmo-folder-length (elmo-pipe-folder-dst-internal folder)))

(luna-define-method elmo-folder-count-flags ((folder elmo-pipe-folder))
  (elmo-folder-count-flags (elmo-pipe-folder-dst-internal folder)))

(luna-define-method elmo-message-flags ((folder elmo-pipe-folder) number)
  (elmo-message-flags (elmo-pipe-folder-dst-internal folder) number))

(luna-define-method elmo-message-field ((folder elmo-pipe-folder)
					number field)
  (elmo-message-field (elmo-pipe-folder-dst-internal folder)
		      number
		      field))

(luna-define-method elmo-message-set-cached ((folder elmo-pipe-folder)
					     number cached)
  (elmo-message-set-cached (elmo-pipe-folder-dst-internal folder)
			   number cached))

(luna-define-method elmo-find-fetch-strategy
  ((folder elmo-pipe-folder) entity &optional ignore-cache)
  (elmo-find-fetch-strategy (elmo-pipe-folder-dst-internal folder)
			    (elmo-message-entity
			     (elmo-pipe-folder-dst-internal folder)
			     (elmo-message-entity-number entity))
			    ignore-cache))

(luna-define-method elmo-message-entity ((folder elmo-pipe-folder) key)
  (elmo-message-entity (elmo-pipe-folder-dst-internal folder) key))

(luna-define-method elmo-message-folder ((folder elmo-pipe-folder)
					 number)
  (elmo-pipe-folder-dst-internal folder))
					     
(require 'product)
(product-provide (provide 'elmo-pipe) (require 'elmo-version))

;;; elmo-pipe.el ends here
