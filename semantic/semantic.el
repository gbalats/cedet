;;; semantic.el --- Semantic buffer evaluator.

;;; Copyright (C) 1999, 2000 Eric M. Ludlam

;; Author: Eric M. Ludlam <zappo@gnu.org>
;; Version: 0.1
;; Keywords: syntax
;; X-RCS: $Id: semantic.el,v 1.18 2000-04-14 21:32:37 zappo Exp $

;; This file is part of GNU Emacs.

;; GNU Emacs is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 2, or (at your option)
;; any later version.

;; GNU Emacs is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to the
;; Free Software Foundation, Inc., 59 Temple Place - Suite 330,
;; Boston, MA 02111-1307, USA.

;;; Commentary:
;;
;; API for determining semantic content of a buffer.  The mode using
;; semantic must be a deterministic programming language.
;;
;; The output of a semantic bovine parse is parse tree.  While it is
;; possible to assign actions in the bovine-table in a similar fashion
;; to bison, this is not it's end goal.
;;
;; Bovine Table Tips & Tricks:
;; ---------------------------
;;
;; Many of the tricks needed to create rules in bison or yacc can be
;; used here.  The exceptions to this rule are that there is no need to
;; declare bison tokens, and you cannot put "code" in the middle of a
;; match rule.  In addition, you should avoid empty matching rules as
;; I haven't quite gotten those to be reliable yet.
;;
;; The top-level bovine table is an association list of all the rules
;; needed to parse your language, or language segment.  It is easiest
;; to create one master rule file, and call the semantic bovinator on
;; subsections passing down the nonterminal rule you want to match.
;;
;; Thus, every entry in the bovine table is of the form:
;; ( NONTERMINAL-SYMBOL MATCH-LIST )
;; 
;; The nonterminal symbol is equivalent to the bison RESULT, and the
;; MATCH-LIST is equivalent to the bison COMPONENTS.  Thus, the bison
;; rule:
;;        expseq: expseq1
;;              | expseq2
;;              ;
;; becomes:
;;        ( expseq ( expseq1 ) ( expseq2 ) )
;; which defines RESULT expseq which can be either COMPONENT expseq1
;; or expseq2.  These two table entries also use nonterminal results,
;; and also use the DEFAULT RESULT LAMBDA (see below for details on
;; the RESULT LAMBDA).
;;
;; You can also have recursive rules, as in bison.  For example the
;; bison rule:
;;        expseq1: exp
;;               | expseq1 ',' exp
;;               ;
;; becomes:
;;        (expseq1 (exp)
;;                 (expseq1 punctuation "," exp
;;                          (lambda (val start end)
;;                                  ( -generator code- ))))
;;
;; This time, the second rule uses it's own RESULT LAMBDA.
;;
;; Lastly, you can also have STRING LITERALS in your rules, though
;; these are different from Bison.  As can be seen above, a literal is
;; a constant lexed symbol, such as `punctuation', followed by a string
;; which is a *regular expression* which must match, or this rule will
;; fail.
;;
;; In BISON, a given rule can have inline ACTIONS.  In the semantic
;; bovinator, there can be only one ACTION which I will refer to here
;; as the RESULT LAMBDA.  There are two default RESULT LAMBDAs which
;; can be used which cover the default case.  The RESULT LAMBDA must
;; return a valid nonterminal token.  A nonterminal token is always of the
;; form ( NAME TOKEN VALUE1 VALUE2 ... START END).  NAME is the name
;; to use for this token.  It is first so that a list of tokens is
;; also an alist, or completion table.  Token should be the same
;; symbol as the nonterminal token generated, though it does not have to
;; be.  The values can be anything you want, including other tokens.
;; START and END indicate where in the buffer this token is, and is
;; easily derived from the START and END parameter passed down.
;;
;; A RESULT LAMBDA must take three parameters, VALS, START and END.
;; VALS is the list of literals derived during the bovination of the
;; match list, including punctuation, parens, and explicit
;; matches.  other elements
;;
;; Here are some example match lists and their code:
;;
;; (expression (lambda (vals start end)
;;                     (append (car vals) (list start end))))
;;
;; In this RESULT LAMBDA, VALS will be of length one, and it's first
;; element will contain the nonterminal expression result.  It is
;; likely to use a rule like this when there is a top level nonterminal
;; symbol whose contents are several other single nonterminal rules.
;; Because of this, we want to result that value with our START and END
;; appended.
;;
;; NOTE: nonterminal values passed in as VALS always have their
;;       START/END parts stripped!
;;
;; This example lambda is also one of the DEFAULT lambdas for the case
;; of a single nonterminal result.  Thus, the above rule could also be
;; written as (expression).
;;
;; A more complex example uses more flex elements.  Lets match this:
;;
;;    (defun myfunction (arguments) "docstring" ...)
;;
;; If we assume a flex depth of 1, we can write it this way:
;;
;; (open-paren "(" symbol "defun" symbol semantic-list string
;;             (lambda (vals start end)
;;                     (list (nth 2 vals) 'function nil (nth 3 vals)
;;                           (nth 4 vals) start end)))
;;
;; The above will create a function token, whose format is
;; predefined.  (See the symbol `semantic-toplevel-bovine-table' for
;; details on some default symbols that should be provided.)
;;
;; From this we can see that VALS will have the value:
;; ( "(" "defun" "myfunction" "(arguments)" "docstring")
;;
;; If we also want to return a list of arguments in our function
;; token, we can replace `semantic-list' with the following recursive
;; nonterminal rule.
;;
;; ( arg-list (semantic-list
;;             (lambda (vals start end)
;;                (semantic-bovinate-from-nonterminal start end 'argsyms))))
;; ( argsyms
;;   (open-paren argsyms (lambda (vals start end)
;;			   (append (car (cdr vals)) (list start end))))
;;   (symbol argsyms (lambda (vals start end)
;;		       (append (cons (car vals) (car (cdr vals)))
;;			       (list start end))))
;;   (symbol close-paren (lambda (vals start end)
;;			   (list (car vals) start end))))
;;
;; This recursive rule can find a parenthetic list with any number of
;; symbols in it.
;;
;; Here we also see a new function, `semantic-bovinate-from-nonterminal'.
;; This function takes START END and a nonterminal result symbol to
;; match.  This will return a complete token, including START and
;; END.  This function should ONLY BE USED IN A RESULT LAMBDA.  It
;; uses knowledge of that scope to reduce the number of parameters
;; that need to be passed in.  This is useful for decomposing complex
;; syntactic elements, such as semantic-list.
;;
;; Token's and the VALS argument
;; -----------------------------
;;
;; Not all syntactic tokens are represented by strings in the VALS argument
;; to the match-list lambda expression.  Some are a dotted pair (START . END).
;; The following are represented as strings:
;;  1) symbols
;;  2) punctuation
;;  3) open/close-paren
;;  4) charquote
;;  5) strings
;; The following are represented as a dotted-pair.
;;  1) semantic-list
;;  2) comments
;; Nonterminals are always lists which are generated in the lambda
;; expression.
;;
;; Semantic Bovine Table Debugger
;; ------------------------------
;;
;; The bovinator also includes a primitive debugger.  This debugger
;; walks through the parsing process and see how it's being
;; interpretted.  There are two steps in debuggin a bovine table.
;;
;; First, place the cursor in the source code where the table is
;; defined.  Execute the command `semantic-bovinate-debug-set-table'.
;; This tells the debugger where you table is.
;;
;; Next, place the cursor in a buffer you which to run the bovinator
;; on, and execute the command `semantic-bovinate-buffer-debug'.  This
;; will parse the table, and highlight the relevant areas and walk
;; through the match list with the cursor, displaying the current list
;; of values (which is always backwards.)
;;
;; DESIGN ISSUES:
;; -------------
;;
;;  At the moment, the only thing I really dislike is the RESULT
;;  LAMBDA format.  While having some good defaults is nice, the use
;;  of append and list in the lambda seems unnecessarily complex.
;;
;;  Also of issue, I am still not sure I like the idea of stripping
;;  BEGIN/END off of nonterminal tokens passed down in VALS.  While they
;;  are often unnecessary, I can imagine that they could prove useful.
;;  Only time will tell.

;;; History:
;; 

(eval-and-compile
  (condition-case nil
      (require 'working)
    (error
     (progn
       (defmacro working-status-forms (message donestr &rest forms)
	 "Contain a block of code during which a working status is shown."
	 (list 'let (list (list 'msg message) (list 'dstr donestr)
			  '(ref1 0))
	       (cons 'progn forms)))
  
       (defun working-status (&optional percent &rest args)
	 "Called within the macro `working-status-forms', show the status."
	 (message "%s%s" (apply 'format msg args)
		  (if (eq percent t) (concat "... " dstr)
		    (format "... %3d%%" percent ))))
  
       (put 'working-status-forms 'lisp-indent-function 2)))))

;;; Code:
(defvar semantic-edebug nil
  "When non-nil, activate the interactive parsing debugger.
Do not set this yourself.  Call `semantic-bovinate-buffer-debug'.")


(defcustom semantic-dump-parse nil
  "When non-nil, dump parsing information."
  :group 'semantic
  :type 'boolean)

(defvar semantic-toplevel-bovine-table nil
  "Variable that defines how to bovinate top level items in a buffer.
Set this in your major mode to return function and variable semantic
types.

The format of a BOVINE-TABLE is:

 ( ( NONTERMINAL-SYMBOL1 MATCH-LIST1 )
   ( NONTERMINAL-SYMBOL2 MATCH-LIST2 )
   ...
   ( NONTERMINAL-SYMBOLn MATCH-LISTn )
 
Where each NONTERMINAL-SYMBOL is an artificial symbol which can appear
in any child sate.  As a starting place, one of the NONTERMINAL-SYMBOLS
must be `bovine-toplevel'.

A MATCH-LIST is a list of possible matches of the form:

 ( STATE-LIST1
   STATE-LIST2
   ...
   STATE-LISTN )

where STATE-LIST is of the form:
  ( TYPE1 [ \"VALUE1\" ] TYPE2 [ \"VALUE2\" ] ... LAMBDA )

where TYPE is one of the returned types of the token stream.
VALUE is a value, or range of values to match against.  For
example, a SYMBOL might need to match \"foo\".  Some TYPES will not
have matching criteria.

LAMBDA is a lambda expression which is evaled with the text of the
type when it is found.  It is passed the list of all buffer text
elements found since the last lambda expression.  It should return a
semantic element (see below.)

For consistency between languages, always use the following symbol
forms.  It is fine to create new symbols, or to exclude some if they
do not exist, however by using these symbols, you can maximize the
number of language-independent programs available for use.

GENERIC ENTRIES:

 Bovine table entry return elements are up to the table author.  It is
recommended, however, that the following format be used.

 (\"NAME\" type-symbol [\"TYPE\"] ... \"DOCSTRING\" START END)

Where type-symbol is the type of return token found, and NAME is it's
name.  If there is any typing informatin needed to describe this
entry, make that come next.  Next, any information you want follows
the optional type.  The last data entry can be the DOCSTRING.  A
docstring does not have to exist in the form used by Emacs Lisp.  It
could be the text of a comment appearing just before a function call,
or in line with a variable.  Lastly, make sure the last two elements
are START and END.

It may seem odd to place NAME in slot 0, and the type-symbol in slot
1, but this turns the returned elements into an alist based on name.
This makes it ideal for passing into generic sorters, string
completion functions, and list searching functions.

In the below entry formats, \"NAME\" is a string which is the name of
the object in question.  It is possible for this to be nil in some
situations, and code dealing with entries should try to be aware of
these situations.

\"TYPE\" is a string representing the type of some objects.  For a
variable, this could very well be another top level token representing
a type nonterminal.

TOP-LEVEL ENTRIES:

 (\"NAME\" variable \"TYPE\" CONST DEFAULT-VALUE MODIFIERS \"DOCSTRING\"
           START END)
   The definition of a variable, or constant.  CONST is a boolean representing
   if this variable is considered a constant.  DEFAULT-VALUE can be
   something apropriate such a a string, or list of parsed elements.
   MODIFIERS are details about a variable that are not covered in the TYPE
   field.  DOCSTRING is optional.

 (\"NAME\" function \"TYPE\" ( ARG-LIST ) \"DOCSTRING\" START END)
   A function/procedure definition.  DOCSTRING is optional.
   ARG-LIST is a list of variable definitions.

 (\"NAME\" type \"TYPE\" ( PART-LIST ) ( PARENTS ) \"DOCSTRING\" START END)
   A type definition.  TYPE of a type could be anything, such as (in C)
   struct, union, typedef, or class.  The PART-LIST is only useful for
   structs that have multiple individual parts.  (It is recommended
   that these be variables, functions or types).  PARENTS is strictly for
   classes where there is inheritance.

 (\"FILE\" include \"DOCSTRING\" START END)
   In C, an #include statement.  In elisp, a require statement.
   Indicates additional locations of sources or definitions.

OTHER ENTRIES:")
(make-variable-buffer-local 'semantic-toplevel-bovine-table)

(defvar semantic-expand-nonterminal nil
  "Function to call for each returned Non-terminal.
Return a list of non-terminals derived from the first argument, or nil
if it does not need to be expanded.")
(make-variable-buffer-local 'semantic-expand-nonterminal)

(defvar semantic-toplevel-bovine-cache nil
  "A cached copy of a recent bovination, plus state.
If no significant changes have been made (based on the state) then
this is returned instead of re-parsing the buffer.")
(make-variable-buffer-local 'semantic-toplevel-bovine-cache)

(defvar semantic-toplevel-bovinate-override nil
  "Local variable set by major modes which provide their own bovination.
This function should behave as the function `semantic-bovinate-toplevel'.")
(make-variable-buffer-local 'semantic-toplevel-bovinate-override)


;;; Utility API functions
;;
;; These functions use the flex and bovination engines to perform some
;; simple tasks useful to other programs.
;;
(defmacro semantic-clear-toplevel-cache ()
  "Clear the toplevel bovin cache for the current buffer."
  '(setq semantic-toplevel-bovine-cache nil))

(defmacro semantic-token-token (token)
  "Retrieve from TOKEN the token identifier."
  `(nth 1 ,token))

(defmacro semantic-token-name (token)
  "Retrieve the name of TOKEN."
  `(car ,token))

(defmacro semantic-token-docstring (token)
  "Retrieve the doc string of TOKEN."
  `(nth (- (length ,token) 3) ,token))

(defmacro semantic-token-start (token)
  "Retrieve the start location of TOKEN."
  `(nth (- (length ,token) 2) ,token))

(defmacro semantic-token-end (token)
  "Retrieve the end location of TOKEN."
  `(nth (- (length ,token) 1) ,token))

(defmacro semantic-token-type (token)
  "Retrieve the type of TOKEN."
  `(nth 2 ,token))

(defmacro semantic-token-type-parts (token)
  "Retrieve the parts of TOKEN."
  `(nth 3 ,token))

(defmacro semantic-token-type-parent (token)
  "Retrieve the parent of TOKEN."
  `(nth 4 ,token))

(defmacro semantic-token-function-args (token)
  "Retrieve the type of TOKEN."
  `(nth 3 ,token))

(defmacro semantic-token-type-parts (token)
  "Retrieve the type of TOKEN."
  `(nth 3 ,token))

(defmacro semantic-token-variable-const (token)
  "Retrieve the status of constantness from variable TOKEN."
  `(nth 3 ,token))

(defmacro semantic-token-variable-default (token)
  "Retrieve the default value of TOKEN."
  `(nth 4 ,token))

(defmacro semantic-token-variable-modifiers (token)
  "Retrieve extra modifiers for the variable TOKEN."
  `(nth 5 ,token))


(defun semantic-token-p (token)
  "Return non-nil if TOKEN is most likely a semantic token."
  (and (listp token)
       (stringp (car token))
       (symbolp (car (cdr token)))))

;;;###autoload
(defun semantic-bovinate-toplevel (&optional depth trashcomments)
  "Bovinate the entire current buffer to a list depth of DEPTH.
DEPTH is optional, and defaults to 0.
Optional argument TRASHCOMMENTS indicates that comments should be
stripped from the main list of synthesized tokens."
  (cond
   (semantic-toplevel-bovinate-override
    (funcall semantic-toplevel-bovinate-override depth trashcomments))
   ((and semantic-toplevel-bovine-cache
	 (car semantic-toplevel-bovine-cache)
	 ;; Add a rule that knows how to see if there have been "big chagnes"
	 )
    (car semantic-toplevel-bovine-cache))
   (t
    (let ((ss (semantic-flex (point-min) (point-max) (or depth 0)))
	  (res nil))
      ;; Init a dump
      (if semantic-dump-parse (semantic-dump-buffer-init))
      ;; Parse!
      (working-status-forms "Scanning" "done"
	(while ss
	  (if (not (and trashcomments (eq (car (car ss)) 'comment)))
	      (let ((nontermsym
		     (semantic-bovinate-nonterminal
		      ss semantic-toplevel-bovine-table))
		    (tmpet nil))
		(if (not nontermsym)
		    (error "Parse error @ %d" (car (cdr (car ss)))))
		(if (car (cdr nontermsym))
		    (progn
		      (if semantic-expand-nonterminal
			  (setq tmpet (funcall semantic-expand-nonterminal
					       (car (cdr nontermsym)))))
		      (if (not tmpet)
			  (setq tmpet (list (car (cdr nontermsym)))))
		      (setq res (append tmpet res)))
					;(error "Parse error")
		  )
		;; Designated to ignore.
		(setq ss (car nontermsym)))
	    (setq ss (cdr ss)))
	  (working-status
	   (if ss
	       (floor
		(* 100.0 (/ (float (car (cdr (car ss))))
			    (float (point-max)))))
	     100)))
	(working-status t))
      (setq semantic-toplevel-bovine-cache (list (nreverse res) (point-max)))
      (car semantic-toplevel-bovine-cache)))))

;;; Behavioral APIs
;;
;; Each major mode will want to support a specific set of behaviors.
;; Usually generic behaviors that need just a little bit of local
;; specifics.  This section permits the setting of override functions
;; for tasks of that nature, and also provides reasonable defaults.

(defvar semantic-override-table nil
  "Buffer local semantic function overrides alist.
These overrides provide a hook for a `major-mode' to override specific
behaviors with respect to generated semantic toplevel nonterminals and
things that these non-terminals are useful for.
Each element must be of the form: (SYM . FUN)
where SYM is the symbol to override, and FUN is the function to
override it with.
Available override symbols:

  SYBMOL                 PARAMETERS              DESCRIPTION
 `find-dependency'       (buffer token & parent)  find the dependency file
 `find-nonterminal'      (buffer token & parent)  find token in buffer.
 `summerize-nonterminal' (token & parent)         return summery string.
 `prototype-nonterminal' (token)                  return a prototype string.

Parameters mean:

  &      - Following parameters are optional
  buffer - The buffer in which a token was found.
  token  - The nonterminal token we are doing stuff with
  parent - If a TOKEN is stripped (of positional infomration) then
           this will be the parent token which should have positional
           information in it.")
(make-variable-buffer-local 'semantic-override-table)

(defun semantic-fetch-overload (sym)
  "Find and return the overload function for SYM."
  (let ((a (assq sym semantic-override-table)))
    (cdr a)))

(defun semantic-find-nonterminal (buffer token &optional parent)
  "Find the location from BUFFER belonging to TOKEN.
TOKEN may be a stripped element, in which case PARENT specifies a
parent token that has position information.
Different behaviors are provided depending on the type of token.
For example, dependencies (includes) will seek out the file that is
depended on, and functions will move to the specified definition."
  (if (or (not (bufferp buffer)) (not token))
      (error "Semantic-find-nonterminal: specify BUFFER and TOKEN"))
  
  (if (if (eq (semantic-token-token token) 'include)
	  (let ((s (semantic-fetch-overload 'find-dependency)))
	    (if s
		(progn (funcall s buffer token) t)
	      t))
	t)
      (let ((s (semantic-fetch-overload 'find-nonterminal)))
	(if s (funcall s buffer token)
	  (let ((start (semantic-token-start token)))
	    (if (numberp start)
		;; If it's a number, go there
		(goto-char start)
	      ;; Otherwise, it's a trimmed vector, such as a parameter,
	      ;; or a structure part.
	      (if (not parent)
		  nil
		(goto-char (semantic-token-start parent))
		;; Here we make an assumtion that the text returned by
		;; the bovinator and concocted by us actually exists
		;; in the buffer.
		(re-search-forward (semantic-token-name token) nil t))))))))

(defun semantic-summerize-nonterminal (token &optional parent)
  "Summerize TOKEN in a reasonable way.
Optional argument PARENT is the parent type if TOKEN is a detail."
  (let ((s (semantic-fetch-overload 'prototype-nonterminal))
	tt)
    (if s
	(funcall s token parent)
      (setq tt (semantic-token-token token))
      ;; FLESH THIS OUT MORE
      (concat (capitalize (symbol-name tt)) ": "
	      (let* ((type (semantic-token-type token))
		     (tok (semantic-token-token token))
		     (args (cond ((eq tok 'function)
				  (semantic-token-function-args token))
				 ((eq tok 'type)
				  (semantic-token-type-parts token))
				 (t nil)))
		     (mods (if (eq tok 'variable)
			       (semantic-token-variable-modifiers token))))
		(if args
		    (setq args
			  (concat " " (if (eq tok 'type) "{" "(")
				  (if (stringp (car args))
				      (mapconcat (lambda (a) a) args " ")
				    (mapconcat 'car args " "))
				   (if (eq tok 'type) "}" ")"))))
		(if (and type (listp type))
		    (setq type (car type)))
		(concat (if type (concat type " "))
			(semantic-token-name token)
			(or args "")
			(or mods "")))))))

(defun semantic-prototype-nonterminal (token)
  "Return a prototype for TOKEN.
This functin must be overloaded, though it need not be used."
  (let ((s (semantic-fetch-overload 'summerize-nonterminal)))
    (if s
	(funcall s token prototype)
      (error "No generic implementation for prototypeing nonterminals"))))

;;; Semantic Table debugging
;;
(defun semantic-dump-buffer-init ()
  "Initialize the semantic dump buffer."
  (save-excursion
    (let ((obn (buffer-name)))
      (set-buffer (get-buffer-create "*Semantic Dump*"))
      (erase-buffer)
      (insert "Parse dump of " obn "\n\n")
      (insert (format "%-15s %-15s %10s %s\n\n"
		      "Nonterm" "Comment" "Text" "Context"))
      )))

(defun semantic-dump-detail (lse nonterminal text comment)
  "Dump info about this match.
Argument LSE is the current syntactic element.
Argument NONTERMINAL is the nonterminal matched.
Argument TEXT is the text to match.
Argument COMMENT is additional description."
  (save-excursion
    (set-buffer "*Semantic Dump*")
    (goto-char (point-max))
    (insert (format "%-15S %-15s %10s %S\n" nonterminal comment text lse)))
  )

(defvar semantic-bovinate-debug-table nil
  "A marker where the current table we are debugging is.")

(defun semantic-bovinate-debug-set-table ()
  "Set the table for the next debug to be here."
  (interactive)
  (if (not (eq major-mode 'emacs-lisp-mode))
      (error "Not an Emacs Lisp file"))
  (beginning-of-defun)
  (setq semantic-bovinate-debug-table (point-marker)))

(defun semantic-bovinate-debug-buffer ()
  "Bovinate the current buffer in debug mode."
  (interactive)
  (if (not semantic-bovinate-debug-table)
      (error
       "Call `semantic-bovinate-debug-set-table' from your semantic table"))
  (let ((semantic-edebug t))
    (delete-other-windows)
    (split-window-vertically)
    (switch-to-buffer (marker-buffer semantic-bovinate-debug-table))
    (other-window 1)
    (semantic-bovinate-toplevel nil t)))

(defun semantic-bovinate-show (lse nonterminal matchlen tokenlen collection)
  "Display some info about the current parse.
Returns 'fail if the user quits, nil otherwise.
LSE is the current listed syntax element.
NONTERMINAL is the current nonterminal being parsed.
MATCHLEN is the number of match lists tried.
TOKENLEN is the number of match tokens tried.
COLLECTION is the list of things collected so far."
  (let ((ol1 nil) (ol2 nil) (ret nil))
    (unwind-protect
	(progn
	  (goto-char (car (cdr lse)))
	  (setq ol1 (make-overlay (car (cdr lse)) (cdr (cdr lse))))
	  (overlay-put ol1 'face 'highlight)
	  (goto-char (car (cdr lse)))
	  (if window-system nil (sit-for 1))
	  (other-window 1)
	  (set-buffer (marker-buffer semantic-bovinate-debug-table))
	  (goto-char semantic-bovinate-debug-table)
	  (re-search-forward
	   (concat "^\\s-*\\((\\|['`]((\\)\\(" (symbol-name nonterminal)
		   "\\)[ \t\n]+(")
	   nil t)
	  (setq ol2 (make-overlay (match-beginning 2) (match-end 2)))
	  (overlay-put ol2 'face 'highlight)
	  (forward-char -2)
	  (forward-list matchlen)
	  (skip-chars-forward " \t\n(")
	  (forward-sexp tokenlen)
	  (message "%s: %S" lse collection)
	  (let ((e (read-event)))
	    (cond ((eq e ?f)		;force a failure on this symbol.
		   (setq ret 'fail))
		  (t nil)))
	  (other-window 1)
	  )
      (delete-overlay ol1)
      (delete-overlay ol2))
    ret))

(defun bovinate ()
  "Bovinate the current buffer.  Show output in a temp buffer."
  (interactive)
  (let ((out (semantic-bovinate-toplevel nil t)))
    (pop-to-buffer "*BOVINATE*")
    (require 'pp)
    (erase-buffer)
    (insert (pp-to-string out))))

(defun bovinate-debug ()
  "Bovinate the current buffer and run in debug mode."
  (interactive)
  (let ((semantic-edebug t)
	(out (semantic-bovinate-debug-buffer)))
    (pop-to-buffer "*BOVINATE*")
    (require 'pp)
    (erase-buffer)
    (insert (pp-to-string out))))


;;; Semantic Bovination
;;
;; Take a semantic token stream, and convert it using the bovinator.
;; The bovinator takes a state table, and converts the token stream
;; into a new semantic stream defined by the bovination table.
;;
(defun semantic-bovinate-nonterminal (stream table &optional nonterminal)
  "Bovinate STREAM based on the TABLE of nonterminal symbols.
Optional argument NONTERMINAL is the nonterminal symbol to start with.
Use `bovine-toplevel' if it is not provided."
  (if (not nonterminal) (setq nonterminal 'bovine-toplevel))
  (let ((ml (assq nonterminal table)))
    (semantic-bovinate-stream stream (cdr ml) table)))

(defun semantic-bovinate-symbol-nonterminal-p (sym table)
  "Return non-nil if SYM is in TABLE, indicating it is NONTERMINAL."
  ;; sym is always a sym, so assq should be ok.
  (if (assq sym table) t nil))

(defun semantic-bovinate-stream (stream matchlist table)
  "Bovinate STREAM using MATCHLIST resolving nonterminals with TABLE.
This is the core routine for converting a stream into a table.
See the variable `semantic-toplevel-bovine-table' for details on the
format of MATCHLIST.
Return the list (STREAM SEMANTIC-STREAM) where STREAM are those
elements of STREAM that have not been used.  SEMANTIC-STREAM is the
list of semantic tokens found."
  (let ((s   nil)			;Temp Stream Tracker
	(lse nil)			;Local Semantic Element
	(lte nil)			;Local matchlist element
	(tev nil)			;Matchlist entry values from buffer
	(val nil)			;Value found in buffer.
	(cvl nil)			;collected values list.
	(out nil)			;Output
	(s-stack nil)			;rollback stream stack
	(start nil)			;the beginning and end.
	(end nil)
	(db-mlen (length matchlist))
	(db-tlen 0)
	)
    ;; prime the rollback stack
    (setq s-stack (cons stream s-stack)
	  start (car (cdr (car stream))))
    (while matchlist
      (setq s (car s-stack)		;init s from the stack.
	    cvl nil			;re-init the collected value list.
	    lte (car matchlist)		;Get the local matchlist entry.
	    db-tlen (length lte))	;length of the local match.
      (if (listp (car lte))
	  ;; In this case, we have an EMPTY match!  Make stuff up.
	  (setq cvl (list nil)))
      (while (and lte (not (or (byte-code-function-p (car lte))
			       (listp (car lte)))))
	;; debugging!
	(if (and lte semantic-edebug)
	    ;; The below reference to nonterminal is a hack and the byte
	    ;; compiler will complain about it.
	    (let ((r (semantic-bovinate-show (car s) nonterminal
					     (- db-mlen (length matchlist))
					     (- db-tlen (length lte))
					     cvl)))
	      (cond ((eq r 'fail)
		     (setq lte '(trash 0 . 0)))
		    (t nil))))
	(if (semantic-bovinate-symbol-nonterminal-p (car lte) table)
	    ;; We have a nonterminal symbol.  Recurse inline.
	    (let ((nontermout (semantic-bovinate-nonterminal s table (car lte))))
	      (setq s (car nontermout)
		    val (car (cdr nontermout)))
	      (if val
		  (let ((len (length val))
			(strip (nreverse (cdr (cdr (reverse val))))))
		    (if semantic-dump-parse
			(semantic-dump-detail (cdr nontermout)
					      (car lte)
					      ""
					      "NonTerm Match"))
		    (setq end (nth (1- len) val) ;reset end to the end of exp
			  cvl (cons strip cvl) ;prepend value of exp
			  lte (cdr lte)) ;update the local table entry
		    )
		;; No value means that we need to terminate this match.
		(setq lte nil cvl nil)) ;No match, exit
	      )

	  (setq lse (car s)		;Get the local stream element
		s (cdr s))		;update stream.
	  ;; trash comments if it's turned on
	  (while (eq (car (car s)) 'comment)
	    (setq s (cdr s)))
	  ;; Do the compare
	  (if (eq (car lte) (car lse))	;syntactic match
	      (let ((valdot (cdr lse)))
		(setq val (semantic-flex-text lse))
		;; DEBUG SECTION
		(if semantic-dump-parse
		    (semantic-dump-detail
		     (if (stringp (car (cdr lte)))
			 (list (car (cdr lte)) (car lte))
		       (list (car lte)))
		     nonterminal val
		     (if (stringp (car (cdr lte)))
			 (if (string-match (car (cdr lte)) val)
			     "Term Match" "Term Fail")
		       "Term Type=")))
		;; END DEBUG SECTION
		(setq lte (cdr lte))
		(if (stringp (car lte))
		    (progn
		      (setq tev (car lte)
			    lte (cdr lte))
		      (if (string-match tev val)
			  (setq cvl (cons val cvl)) ;append this value
			(setq lte nil cvl nil))) ;clear the entry (exit)
		  (setq cvl (cons
			     (if (member (car lse)
					 '(comment semantic-list))
				 valdot val) cvl))) ;append unchecked value.
		(setq end (cdr (cdr lse))))
	    (if (and semantic-dump-parse nil)
		(semantic-dump-detail (car lte)
				      nonterminal (semantic-flex-text lse)
				      "Term Type Fail"))
	    (setq lte nil cvl nil)) 	;No more matches, exit
	  ))
      (if (not cvl)			;lte=nil;  there was no match.
	  (setq matchlist (cdr matchlist)) ;Move to next matchlist entry
	(setq out (if (car lte)
		      (apply (car lte)	;call matchlist fn on values
			     (nreverse cvl) start (list end))
		    (cond ((and (= (length cvl) 1)
				(listp (car cvl))
				(not (numberp (car (car cvl)))) )
			   (append (car cvl) (list start end)))
			  (t
			   (append (nreverse cvl) (list start end))))
		    )
	      matchlist nil)		;generate exit condition
	;; Nothin?
	))
    (list s out)))

(defun semantic-bovinate-from-nonterminal (start end nonterm &optional depth)
  "Bovinate from within a nonterminal lambda from START to END.
Depends on the existing environment created by `semantic-bovinate-stream'.
Argument NONTERM is the nonterminal symbol to start with.
Optional argument DEPTH is the depth of lists to dive into.
Whan used in a `lambda' of a MATCH-LIST, there is no need to include
a START and END part."
  (let* ((stream (semantic-flex start end (or depth 1)))
	 (ans (semantic-bovinate-nonterminal
	       stream
	       ;; the byte compiler will complain about this one.
	       table
	       nonterm)))
    (car (cdr ans))))

;;; Semantic Flexing
;;
;; This is a simple scanner which uses the syntax table to generate
;; a stream of simple tokens.
;;
;; A flex element is of the form:
;;  (SYMBOL START . END)
;; Where symbol is the type of thing it is.  START and END mark that
;; objects boundary.

(defvar semantic-flex-extensions nil
  "Buffer local extensions to the the lexical analyzer.
This should contain an alist with a key of a regex and a data element of
a function.  The function should both move point, and return a lexical
token of the form ( TYPE START .  END).  nil is also a valid return.")
(make-variable-buffer-local 'semantic-flex-extensions)

(defun semantic-flex-buffer (&optional depth)
  "Sematically flex the current buffer.
Optional argument DEPTH is the depth to scan into lists."
  (semantic-flex (point-min) (point-max) depth))

(defun semantic-flex (start end &optional depth)
  "Using the syntax table, do something roughly equivalent to flex.
Semantically check between START and END.  Optional argument DEPTH
indicates at what level to scan over entire lists.
The return value is a token stream.  Each element being a list, such
as (symbol start-expression .  end-expresssion)."
  ;(message "Flexing muscles...")
  (let ((ts nil)
	(sym nil)
	(pos (point))
	(ep nil)
	(curdepth 0)
	(cs (if comment-start-skip
		(concat "\\(\\s<\\|" comment-start-skip "\\)")
	      (concat "\\(\\s<\\)"))))
    (goto-char start)
    (while (< (point) end)
      (cond (;; comment end is also EOL for some languages.
	     (looking-at "\\(\\s-\\|\\s>\\)+"))
	    ((let ((fe semantic-flex-extensions)
		   (r nil))
	       (while fe
		 (if (looking-at (car (car fe)))
		     (setq ts (cons (funcall (cdr (car fe))) ts)
			   r t
			   fe nil
			   ep (point)))
		 (setq fe (cdr fe)))
	       (if (and r (not (car ts))) (setq ts (cdr ts)))
	       r))
	    ((looking-at "\\(\\sw\\|\\s_\\)+")
	     (setq ts (cons (cons 'symbol
				  (cons (match-beginning 0) (match-end 0)))
			    ts)))
	    ((looking-at "\\s\\+")
	     (setq ts (cons (cons 'charquote
				  (cons (match-beginning 0) (match-end 0)))
			    ts)))
	    ((looking-at "\\s(+")
	     (if (or (not depth) (< curdepth depth))
		 (progn
		   (setq curdepth (1+ curdepth))
		   (setq ts (cons (cons 'open-paren
					(cons (match-beginning 0) (match-end 0)))
				  ts)))
	       (setq ts (cons (cons 'semantic-list
				    (cons (match-beginning 0)
					  (save-excursion
					    (forward-list 1)
					    (setq ep (point)))))
			      ts))))
	    ((looking-at "\\s)+")
	     (setq ts (cons (cons 'close-paren
				  (cons (match-beginning 0) (match-end 0)))
			    ts))
	     (setq curdepth (1- curdepth)))
	    ((looking-at "\\s\"")
	     ;; Zing to the end of this string.
	     (setq ts (cons (cons 'string
				  (cons (match-beginning 0)
					(save-excursion
					  (forward-sexp 1)
					  (setq ep (point)))))
			    ts)))
	    ((looking-at cs)
	     ;; Zing to the end of this comment.
	     (if (eq (car (car ts)) 'comment)
		 (setcdr (cdr (car ts)) (save-excursion
					  (forward-comment 1)
					  (setq ep (point))))
	       (setq ts (cons (cons 'comment
				    (cons (match-beginning 0)
					  (save-excursion
					    (forward-comment 1)
					    (setq ep (point)))))
			      ts))))
	    ((looking-at "\\(\\s.\\|\\s$\\|\\s'\\)")
	     (setq ts (cons (cons 'punctuation
				  (cons (match-beginning 0) (match-end 0)))
			    ts)))
	    (t (error "What is that?")))
      (goto-char (or ep (match-end 0)))
      (setq ep nil))
    (goto-char pos)
    ;(message "Flexing muscles...done")
    (nreverse ts)))

(defun semantic-flex-text (semobj)
  "Fetch the text associated with the semantic object SEMOBJ."
  (buffer-substring-no-properties (car (cdr semobj)) (cdr (cdr semobj))))

(defun semantic-flex-list (semlist depth)
  "Flex the body of SEMLIST to DEPTH."
  (semantic-flex (car (cdr semlist)) (cdr (cdr semlist)) depth))

(provide 'semantic)

;;; semantic.el ends here

