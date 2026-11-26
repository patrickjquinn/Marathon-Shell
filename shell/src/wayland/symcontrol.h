#pragma once

class QEvent;
class QObject;
class QWaylandSeat;

// The Q25's Sym key held with a letter KeyRouting::symIsControl() names is
// Ctrl and the letter. Control goes into the seat keyboard's state as a real
// Ctrl key would, so an app's next key with Sym still held keeps its Sym
// meaning.
class SymControl {
  public:
    // A window's key event; true when its Ctrl form went to watched instead.
    bool filter(QObject *watched, QEvent *event, QWaylandSeat *seat);

  private:
    bool m_symHeld = false;
    bool m_sending = false;
    int  m_key     = 0;
};
