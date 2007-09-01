;; -*- package: clpython.test; readtable: py-ast-user-readtable -*-
;;
;; This software is Copyright (c) Franz Inc. and Willem Broekema.
;; Franz Inc. and Willem Broekema grant you the rights to
;; distribute and use this software as governed by the terms
;; of the Lisp Lesser GNU Public License
;; (http://opensource.franz.com/preamble.html),
;; known as the LLGPL.

;;;; Python language semantics test

(in-package :clpython.test)
(in-syntax *user-readtable*)

(defun run-lang-test ()
  (with-subtest (:name "CLPython-Lang")
    (dolist (node '(:assert-stmt :assign-stmt :attributeref-expr :augassign-stmt
		    :backticks-expr :binary-expr :binary-lazy-expr :break-stmt
		    :call-expr :classdef-stmt :comparison-expr :continue-stmt
		    :del-stmt :dict-expr :exec-stmt :for-in-stmt :funcdef-stmt
		    :generator-expr :global-stmt :identifier-expr :if-stmt
		    :import-stmt :import-from-stmt :lambda-expr :listcompr-expr
                    :list-expr :module-stmt :print-stmt :return-stmt :slice-expr
                    :subscription-expr :suite-stmt :return-stmt :raise-stmt
                    :try-except-stmt :try-finally-stmt :tuple-expr :unary-expr
                    :while-stmt :yield-stmt))
      (test-lang node))))

(defmacro with-all-compiler-variants-tried (&body body)
  (let ((g1 (gensym))
        (g2 (gensym)))
    `(dolist (,g1 '(t nil))
       (dolist (,g2 '(t nil))
         (let ((clpython::*use-environment-acccessors* ,g1)
               (clpython::*compile-python-ast-before-running* ,g2))
           ,@body)))))

(defmacro run-error (string condtype &rest options)
  `(with-all-compiler-variants-tried
       (test-error (run-python-string ,string) :condition-type ',condtype ,@options)))

(defmacro run-no-error (string &rest options)
  `(with-all-compiler-variants-tried
       (test-no-error (run-python-string ,string) ,@options)))

(defmacro run-test (val string &rest options)
  `(with-all-compiler-variants-tried
       (test ,val (run-python-string ,string) ,@options)))


(defgeneric test-lang (kind))

(defmethod test-lang :around (kind)
  (with-subtest (:name (format nil "CLPython-Lang-~A" kind))
    (let ((*warn-unused-function-vars* nil))
      (call-next-method))))

(defmethod test-lang ((kind (eql :assert-stmt)))
  (run-error        "assert 0" {AssertionError})
  (run-no-error     "assert 1")
  (run-error "assert \"\"" {AssertionError})
  (run-no-error     "assert \"s\"")
  (run-error "assert []" {AssertionError})
  (run-no-error     "assert [1,2]")
  (run-no-error     "assert True")
  (run-error "assert not True" {AssertionError})
  (run-no-error     "assert not not True")
  (run-no-error     "assert not False")
  
  (multiple-value-bind (x err) 
      (ignore-errors (run-python-string "assert 0, 'abc'"))
    (test-false x)
    (test-true err)
    (test-true (string= (pop (exception-args err)) "abc"))))

(defmethod test-lang ((kind (eql :assign-stmt)))
  (run-test 3 "a = 3; a")
  (run-test 3 "a, = 3,; a")
  (run-test 3 "[a] = [3]; a")
  (run-test 3 "(a,) = (3,); a")
  (run-test 3 "a,b = 3,4; a")
  (run-test 3 "a,b = [3,4]; a")
  (run-error "a,b = 3" {TypeError} :fail-info "Iteration over non-sequence.")
  (run-error "a,b = 3,4,5" {ValueError})
  (run-error "a,b = [3,4,5]" {ValueError}))

(defmethod test-lang ((kind (eql :attributeref-expr)))
  (run-no-error "class C: pass
x = C()
C.a = 3
assert (x.a == 3)
x.a = 4
assert (x.a == 4)
del x.a
assert (x.a == 3)
del C.a
assert not hasattr(C, 'a')"))

(defmethod test-lang ((kind (eql :augassign-stmt)))
  (run-no-error "x = 3; x+= 2; assert x == 5")
  (run-no-error "x = 3; x*= 2; assert x == 6")
  (run-no-error "x = [1,2]; x[1] -= 2; assert x[1] == 0")
  (run-error    "x,y += 3" {SyntaxError}))

(defmethod test-lang ((kind (eql :backticks-expr)))
  (run-no-error "x = `3`; assert x == '3'")
  (run-no-error "x = `(1,3)`; assert x == '(1, 3)'")
  (run-no-error "
class C:
  def __repr__(self): return 'r'
  def __str__(self): return 'str'
x = C()
assert `x` == 'r'"))

(defmethod test-lang ((kind (eql :binary-expr)))
  (run-no-error "assert 1 + 2 == 3")
  (run-no-error "assert 1 - 2 * 3 == -5")
  (run-no-error "assert 1 ^ 3 == 2")
  (run-no-error "assert 1 | 2 == 3")
  (run-no-error "assert 4 * 'ax' == 'axaxaxax'")
  (run-no-error "assert -4 * 'ax' == ''"))

(defmethod test-lang ((kind (eql :binary-lazy-expr)))
  (run-no-error "assert not (0 or 0)")
  (run-no-error "assert not (0 and 0)")
  (run-no-error "1 or 3 / 0")
  (run-no-error "0 and 3/0"))

(defmethod test-lang ((kind (eql :break-stmt)))
  (run-error "break" {SyntaxError})
  (run-no-error "
for i in [1,2]:
  break
assert i == 1"))

(defmethod test-lang ((kind (eql :call-expr)))
  (run-no-error "def f(x,y,z=3,*arg,**kw): return x,y,z,arg,kw
assert (1,2,3,(),{}) == f(1,2)"))

(defmethod test-lang ((kind (eql :classdef-stmt)))
  (run-no-error "
class C:
  def m(self): return 'C.m'
assert C().m() == 'C.m'
assert C.__mro__ == (C, object)")
  (run-no-error "
class C: pass
class D(C): pass
assert D.__mro__ == (D, C, object)")
  (run-no-error "
class C:
  x = 3          # this variable X can not be closed over by methods
  def g(self):
    return x   # so this should give an error

try:
  print C().g()
  assert False
except NameError:
  'ok'
")
  (run-no-error "
def f():
  class C:
    x = 3          # this variable X can not be closed over by methods
    def g(self):
	return x   # so this should give an error
  return C().g

try:
  print f()()
  assert False
except NameError:
  'ok'
")
  (run-no-error "
class M(type): pass

class C:
  __metaclass__ = M

assert type.__class__ == type
assert M.__class__ == type
assert M.__class__.__class__ == type
assert C.__class__ == M")
    (let ((clpython::*mro-filter-implementation-classes* t))
      (run-no-error "
class C(int):
  pass
x = C()
assert x.__class__ == C
assert C.__class__ == type
assert C.__mro__ == (C, int, object)")))

(defmethod test-lang ((kind (eql :comparison-expr)))
  ;; Ensure py-list.__eq__ can handle non-lists, etc.
  (run-no-error "assert [] != ()")
  (run-no-error "assert () != []")
  (run-no-error "assert [] == []")
  (run-no-error "assert [] != {}")
  (run-no-error "assert {} != []")
  (run-no-error "assert [] != None")
  (run-no-error "assert '' != None")
  (run-no-error "assert [] != 3")
  (run-no-error "assert 3 != None"))

(defmethod test-lang ((kind (eql :continue-stmt)))
  (run-error "break" {SyntaxError})
  (run-no-error "for i in []: continue")
  (run-no-error "
for i in [1]: continue
assert i == 1")
  (run-no-error "
for i in [1,2,3]:
  continue
  1 / 0")
  (run-no-error "
sum = 0
for i in [0,1,2,3]:
  if i == 0:
    continue
  sum += i
  continue
  i / 0
assert sum == 1 + 2 + 3
assert i == 3"))

(defmethod test-lang ((kind (eql :del-stmt)))
  (run-error "del x" {NameError})
  (run-no-error "x = 3; del x")
  (run-error "x = 3; del x; x" {NameError})
  (run-no-error "x,y,z = 3,4,5; del x,y; z")
  (run-error "x,y,z = 3,4,5; del x,y; y" {NameError})
  )

(defmethod test-lang ((kind (eql :dict-expr)))
  (run-no-error "{}")
  (run-no-error "{1: 3}")
  (run-no-error "{1+2: 3+4}")
  (run-no-error "assert {1: 3}[1] == 3")
  (run-no-error "assert {1: 3, 2: 4}[1] == 3")
  (run-no-error "
d = {}
d[3] = 1
assert d[3] == 1
del d[3]
assert d == {}
d[3] = 2
assert d[3] == 2")
  (run-no-error "
# make sure user-defined subclasses of string work okay as key
class C(str): pass
x = C('a')
d = {}
d[x] = 3
assert d['a'] == 3
y = C('b')
assert d.get(y) == None
d[y] = 42
assert d[y] == 42
assert d['b'] == 42"))

(defmethod test-lang ((kind (eql :exec-stmt)))
  (run-no-error "
def f():
  x = (1,2)
  exec 'print x'" :fail-info "Make sure tuple `(1 2) is quoted in code generated for `exec'")
  (run-no-error "exec 'assert x == 3' in {'x': 3}")
  (run-no-error "
glo = {'x': 3}
loc = {'x': 4}
exec 'assert x == 4' in glo, loc" :fail-info "Locals higher priority than globals.")
  (run-no-error "
exec \"
try:
  1/0
  assert 0
except ZeroDivisionError:
  'ok'\"")
  (run-no-error "
x = 3
exec 'assert x == 3'")
  (run-no-error "
x = 3
def f():
  x = 4
  exec 'assert x == 4'
f()")
  (run-no-error "
x = 3
def f():
  x = 4
  def g():
    exec 'assert x == 3'
  g()
f()")
  )

(defmethod test-lang ((kind (eql :for-in-stmt)))
  (run-no-error "for i in []: 1/0")
  (run-no-error "for i in '': 1/0")
  (run-no-error "
for k in {1: 3}:
  x = k
assert k == 1")
  (run-no-error "
for x in []:
  pass
else:
  x = 3
assert x == 3")
  (run-no-error "
for x in [1]:
  break
else:
  x = 3
assert x == 1")
  (run-no-error "
def f():
  for x in [1]:
    break
  else:
    x = 3
  assert x == 1
  yield x
g = f()
assert g.next() == 1")
  (run-no-error "
def f():
  for x in []:
    pass
  else:
    x = 3
  yield x
g = f()
assert g.next() == 3"))

(defmethod test-lang ((kind (eql :funcdef-stmt)))
  ;; *-arg, **-arg
  (run-no-error "
def f(a, b, c=13, d=14, *e, **f): return [a,b,c,d,e,f]
x = f(1,2,3,4,5,6)
assert x == [1,2,3,4,(5,6),{}], 'x = %s' % x"
)
  (run-no-error "
def f(a, b, c=13, d=14, *e, **f): return [a,b,c,d,e,f]
x = f(a=1,b=2,c=3,d=4,e=5,f=6)
assert x == [1,2,3,4,(),{'e': 5, 'f': 6}], 'x = %s' % x"
                )
  (run-no-error "
def f(): return f
f()
assert f() == f"))

(defmethod test-lang ((kind (eql :generator-expr)))
  )

(defmethod test-lang ((kind (eql :global-stmt)))
  (test-warning (run-python-string "global x")) ;; useless at toplevel
  (run-error "
def f():
  x = 3
  global x" {SyntaxError}) ;; global decl must be before first usage
  (run-error "def f(x): global x" {SyntaxError})
  (run-no-error "
def f(y):
  global x
  x = y
f(3)
assert x == 3")
  (run-no-error "
def f():
  global x
  def g(y):
    x = y
  return g
f()(4)
assert x == 4" :fail-info "Global decl is also valid for nested functions")
  (test-warning (run-python-string "
global y  # bogus declaration; check it does not leak into f
def f(a):
  y = a
f(3)
try:
  print y
  assert False
except NameError:
  pass"
  )))

(defmethod test-lang ((kind (eql :identifier-expr)))
  )

(defmethod test-lang ((kind (eql :if-stmt)))
  )

(defmethod test-lang ((kind (eql :import-stmt)))
  (run-no-error "import sys
assert sys" :fail-info "Should work in both ANSI and Modern mode.")
  )

(defmethod test-lang ((kind (eql :import-from-stmt)))
  (run-no-error "from sys import path; path.append('/foo')"))

(defmethod test-lang ((kind (eql :lambda-expr)))
  (run-no-error "lambda: None")
  (run-no-error "lambda: 3*x")
  (run-error "(lambda: 3*x)()" {NameError})
  (run-no-error "assert (lambda x: x)(0) == 0")
  (run-no-error "
f = lambda x, y=3: x+y
assert f(1) == 4
assert f(1,2) == 3")
  (run-no-error "
f = lambda x, y=lambda: 42: x + y()
assert f(1) == 1 + 42")
  (run-no-error "
f = lambda x, y=lambda: 42: x + y()
assert f(1, lambda: 2) == 1 + 2")
  )

(defmethod test-lang ((kind (eql :listcompr-expr)))
  )

(defmethod test-lang ((kind (eql :list-expr)))
  )

(defmethod test-lang ((kind (eql :module-stmt)))
  )

(defmethod test-lang ((kind (eql :print-stmt)))
  )

(defmethod test-lang ((kind (eql :return-stmt)))
  )

(defmethod test-lang ((kind (eql :slice-expr)))
  )

(defmethod test-lang ((kind (eql :subscription-expr)))
  )

(defmethod test-lang ((kind (eql :suite-stmt)))
  )

(defmethod test-lang ((kind (eql :raise-stmt)))
  )

(defmethod test-lang ((kind (eql :try-except-stmt)))
  )

(defmethod test-lang ((kind (eql :try-finally-stmt)))
  )

(defmethod test-lang ((kind (eql :tuple-expr)))
  (run-no-error "assert (1,2,3)[0:1] == (1,)"))

(defmethod test-lang ((kind (eql :unary-expr)))
  (run-no-error "x = 3; +x; -x")
  (run-no-error "assert +3 == 3")
  (run-no-error "x = 3; assert +x == 3")
  (run-no-error "x = 3; assert -x == -3")
  (run-no-error "x = 3; assert ++x == 3")
  (run-no-error "x = 3; assert --x == 3")
  )

(defmethod test-lang ((kind (eql :while-stmt)))
  (run-no-error "while 0: 1/0")
  (run-no-error "while 1: break")
  (run-no-error "
x = 3
while x > 0:
  x -= 1
  if x == 1:
    break
assert x == 1"
  )
  (run-no-error "
x = 3
while x > 0:
  x -= 1
  if x == 1:
    break
else:
  x = 42
assert x == 1"
  )
  (run-no-error "
x = 3
while x > 0:
  x -= 1
else:
  x = 42
assert x == 42"
  )
  (run-no-error "
def f():
  x = 3
  while x > 0:
    x -= 1
  else:
    x = 42
  assert x == 42
f()")
  (run-no-error "
def f():
  x = 3
  while x > 0:
    x -= 1
  else:
    x = 42
  assert x == 42
  yield 42
g = f()
assert g.next() == 42"))

(defmethod test-lang ((kind (eql :yield-stmt)))
  )
