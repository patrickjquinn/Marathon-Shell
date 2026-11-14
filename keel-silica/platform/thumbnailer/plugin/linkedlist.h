// SPDX-FileCopyrightText: 2012 Jolla Ltd
// SPDX-License-Identifier: BSD-3-Clause
/*
 * Copyright (C) 2012 Jolla Ltd
 * Contact: Andrew den Exter <andrew.den.exter@jollamobile.com>
 *
 * You may use this file under the terms of the BSD license as follows:
 *
 * "Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are
 * met:
 *   * Redistributions of source code must retain the above copyright
 *     notice, this list of conditions and the following disclaimer.
 *   * Redistributions in binary form must reproduce the above copyright
 *     notice, this list of conditions and the following disclaimer in
 *     the documentation and/or other materials provided with the
 *     distribution.
 *   * Neither the name of Nemo Mobile nor the names of its contributors
 *     may be used to endorse or promote products derived from this
 *     software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
 * "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
 * LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
 * A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
 * OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
 * SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
 * LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
 * DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
 * THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
 * OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE."
 */

#ifndef LINKEDLIST_H
#define LINKEDLIST_H

template<class Parent, typename Member, Member Parent::*member> Parent *memberToParent(Member * const m)
{
    return reinterpret_cast<Parent *>(reinterpret_cast<char *>(m)
                - (reinterpret_cast<const char *>(&(reinterpret_cast<const Parent *>(0)->*member)) - reinterpret_cast<const char *>(0)));
}

template<class Parent, typename Member, Member Parent::*member> const Parent *memberToParent(const Member * const m)
{
    return reinterpret_cast<const Parent *>(reinterpret_cast<const char *>(m)
                - (reinterpret_cast<const char *>(&(reinterpret_cast<const Parent *>(0)->*member)) - reinterpret_cast<const char *>(0)));
}

struct LinkedListNode
{
    LinkedListNode() : next(this), previous(this) {}
    ~LinkedListNode() { previous->next = next; next->previous = previous; }

    void erase() { previous->next = next; next->previous = previous; next = previous = this; }

    LinkedListNode *next;
    LinkedListNode *previous;
};

template <class T, LinkedListNode T::*member>
class LinkedList
{
public:
    class iterator {
    public:
        iterator() : node(0) {}
        iterator(LinkedListNode *node) : node(node) {}
        iterator(const iterator &it) : node(it.node) {}
        iterator operator =(const iterator &it) { node = it.node; return *this; }

        iterator &operator ++() { node = node->next; return *this; }
        iterator &operator --() { node = node->previous; return *this; }
        iterator operator ++(int) { iterator it = *this; node = node->next; return it; }
        iterator operator --(int) { iterator it = *this; node = node->previous; return it; }

        T *operator ->() { return item(); }
        const T *operator ->() const { return item(); }

        T &operator *() { return *item(); }
        const T &operator *() const { return *item(); }

        operator T *() { return item(); }
        operator const T *() const { return item(); }

        bool operator ==(const iterator &it) { return node == it.node; }
        bool operator !=(const iterator &it) { return node != it.node; }

    private:
        T *item() { return memberToParent<T, LinkedListNode, member>(node); }
        const T *item() const { return memberToParent<const T, LinkedListNode, member>(node); }
        LinkedListNode *node;

        friend class LinkedList<T, member>;
    };

    LinkedList() {}
    LinkedList(LinkedList &list) {
        *this = list;
    }
    LinkedList &operator =(LinkedList &list) {
        root.erase();
        if (!list.isEmpty()) {
            root = list.root;
            list.root.next = &list.root;
            list.root.previous = &list.root;
            root.next->previous = &root;
            root.previous->next = &root;
        }
        return *this;
    }
    ~LinkedList() { root.erase(); }

    bool isEmpty() const { return root.next == &root; }

    iterator begin() { return iterator(root.next); }
    iterator end() { return iterator(&root); }

    iterator erase(iterator it) { iterator next(it.node->next); it.node->erase(); return next; }

    T *first() { return root.next != &root ? memberToParent<T, LinkedListNode, member>(root.next) : 0; }
    const T *first() const { return root.next != &root ? memberToParent<const T, LinkedListNode, member>(root.next) : 0; }
    T *last() { return root.next != &root ? memberToParent<T, LinkedListNode, member>(root.previous) : 0; }
    const T *last() const { return root.next != &root ? memberToParent<const T, LinkedListNode, member>(root.previous) : 0; }

    T *takeFirst() { T *item = first(); root.next->erase(); return item; }
    T *takeLast() { T *item = last(); root.previous->erase(); return item; }

    void insertBefore(T *before, T *item) { insertBeforeNode(&(before->*member), &(item->*member)); }
    void insertAfter(T *after, T *item) { insertAfterNode(&(after->*member), &(item->*member)); }

    void append(T *item) { insertBeforeNode(&root, &(item->*member)); }
    void prepend(T *item) { insertAfterNode(&root, &(item->*member)); }

private:
    void insertBeforeNode(LinkedListNode *before, LinkedListNode *node)
    {
        node->erase();

        before->previous->next = node;
        node->next = before;
        node->previous = before->previous;
        before->previous = node;
    }

    void insertAfterNode(LinkedListNode *after, LinkedListNode *node)
    {
        node->erase();

        after->previous->next = after->next;
        node->next = after->next;
        node->previous = after;
        after->next = node;
    }

    LinkedListNode root;
};

#endif
