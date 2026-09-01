// Hand-written declarations for the C libraries the Linux tray links against.
//
// Ubuntu ships the runtime shared objects for GTK 3, GDK, Cairo, GLib and
// libayatana-appindicator3 but the matching -dev headers are a separate
// package. Declaring the handful of entry points Ration actually calls keeps
// the tray buildable on a machine that only has the runtime, and pins the
// surface to something small enough to audit. The signatures follow the
// published C ABI of each library, which is stable across the 3.x series.
#ifndef RATION_LINUX_TRAY_H
#define RATION_LINUX_TRAY_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// MARK: - GLib / GObject

typedef void *gpointer;
typedef int gboolean;
typedef unsigned long gulong;
typedef unsigned int guint;
typedef void (*GCallback)(void);
typedef void (*GClosureNotify)(gpointer data, void *closure);
typedef gboolean (*GSourceFunc)(gpointer user_data);

void g_object_unref(gpointer object);
gpointer g_object_ref_sink(gpointer object);
void g_free(gpointer mem);

gulong g_signal_connect_data(
    gpointer instance, const char *detailed_signal, GCallback c_handler,
    gpointer data, GClosureNotify destroy_data, int connect_flags);

guint g_timeout_add(guint interval_ms, GSourceFunc function, gpointer data);
guint g_idle_add(GSourceFunc function, gpointer data);
gboolean g_source_remove(guint tag);

// MARK: - GDK / GTK opaque types

typedef struct _GtkWidget GtkWidget;
typedef struct _GdkWindow GdkWindow;
typedef struct _GdkDevice GdkDevice;
typedef struct _GdkScreen GdkScreen;
typedef struct _GdkDisplay GdkDisplay;
typedef struct _GdkMonitor GdkMonitor;
typedef struct _GdkSeat GdkSeat;

// GdkRectangle, laid out as in gdk/gdktypes.h.
typedef struct {
    int x;
    int y;
    int width;
    int height;
} GdkRectangle;

// Event records, field-for-field as declared in gdk/gdkevents.h. Only the
// three Ration reads are mirrored; the rest arrive as opaque pointers.
typedef struct {
    int type;
    GdkWindow *window;
    int8_t send_event;
    uint32_t time;
    double x;
    double y;
    double *axes;
    guint state;
    guint button;
    GdkDevice *device;
    double x_root;
    double y_root;
} GdkEventButton;

typedef struct {
    int type;
    GdkWindow *window;
    int8_t send_event;
    uint32_t time;
    double x;
    double y;
    double *axes;
    guint state;
    int16_t is_hint;
    GdkDevice *device;
    double x_root;
    double y_root;
} GdkEventMotion;

typedef struct {
    int type;
    GdkWindow *window;
    int8_t send_event;
    uint32_t time;
    double x;
    double y;
    guint state;
    int direction;
    GdkDevice *device;
    double x_root;
    double y_root;
    double delta_x;
    double delta_y;
    guint is_stop;
} GdkEventScroll;

typedef struct {
    int type;
    GdkWindow *window;
    int8_t send_event;
    uint32_t time;
    guint state;
    guint keyval;
    int length;
    char *string;
    uint16_t hardware_keycode;
    uint8_t group;
    guint is_modifier;
} GdkEventKey;

typedef struct {
    int type;
    GdkWindow *window;
    int8_t send_event;
    int detail;
} GdkEventCrossingHead;

// MARK: - GTK

gboolean gtk_init_check(int *argc, char ***argv);
void gtk_main(void);
void gtk_main_quit(void);
gboolean gtk_events_pending(void);
void gtk_main_iteration(void);

GtkWidget *gtk_window_new(int type);
void gtk_window_set_title(GtkWidget *window, const char *title);
void gtk_window_set_default_size(GtkWidget *window, int width, int height);
void gtk_window_set_decorated(GtkWidget *window, gboolean setting);
void gtk_window_set_resizable(GtkWidget *window, gboolean resizable);
void gtk_window_set_keep_above(GtkWidget *window, gboolean setting);
void gtk_window_set_skip_taskbar_hint(GtkWidget *window, gboolean setting);
void gtk_window_set_skip_pager_hint(GtkWidget *window, gboolean setting);
void gtk_window_set_type_hint(GtkWidget *window, int hint);
void gtk_window_set_position(GtkWidget *window, int position);
void gtk_window_move(GtkWidget *window, int x, int y);
void gtk_window_resize(GtkWidget *window, int width, int height);
void gtk_window_present(GtkWidget *window);
void gtk_window_set_icon_name(GtkWidget *window, const char *name);
void gtk_window_set_startup_id(GtkWidget *window, const char *startup_id);
void gtk_window_get_position(GtkWidget *window, int *root_x, int *root_y);
void gtk_window_get_size(GtkWidget *window, int *width, int *height);

void gtk_widget_show(GtkWidget *widget);
void gtk_widget_show_all(GtkWidget *widget);
void gtk_widget_hide(GtkWidget *widget);
void gtk_widget_destroy(GtkWidget *widget);
gboolean gtk_widget_get_visible(GtkWidget *widget);
void gtk_widget_queue_draw(GtkWidget *widget);
void gtk_widget_add_events(GtkWidget *widget, int events);
void gtk_widget_set_size_request(GtkWidget *widget, int width, int height);
void gtk_widget_set_app_paintable(GtkWidget *widget, gboolean setting);
void gtk_widget_set_visual(GtkWidget *widget, void *visual);
void gtk_widget_set_can_focus(GtkWidget *widget, gboolean can_focus);
void gtk_widget_grab_focus(GtkWidget *widget);
int gtk_widget_get_allocated_width(GtkWidget *widget);
int gtk_widget_get_allocated_height(GtkWidget *widget);
GdkWindow *gtk_widget_get_window(GtkWidget *widget);
GdkScreen *gtk_widget_get_screen(GtkWidget *widget);

void gtk_container_add(GtkWidget *container, GtkWidget *widget);
GtkWidget *gtk_drawing_area_new(void);
GtkWidget *gtk_menu_new(void);
GtkWidget *gtk_menu_item_new_with_label(const char *label);
GtkWidget *gtk_check_menu_item_new_with_label(const char *label);
void gtk_check_menu_item_set_active(GtkWidget *item, gboolean is_active);
gboolean gtk_check_menu_item_get_active(GtkWidget *item);
GtkWidget *gtk_separator_menu_item_new(void);
void gtk_menu_item_set_label(GtkWidget *menu_item, const char *label);
void gtk_menu_shell_append(GtkWidget *menu_shell, GtkWidget *child);
void gtk_menu_item_set_submenu(GtkWidget *menu_item, GtkWidget *submenu);

// MARK: - GDK helpers used for placing the panel under the tray icon

GdkScreen *gdk_screen_get_default(void);
GdkDisplay *gdk_display_get_default(void);
GdkSeat *gdk_display_get_default_seat(GdkDisplay *display);
GdkDevice *gdk_seat_get_pointer(GdkSeat *seat);
void gdk_device_get_position(GdkDevice *device, GdkScreen **screen, int *x, int *y);
GdkMonitor *gdk_display_get_monitor_at_point(GdkDisplay *display, int x, int y);
void gdk_monitor_get_workarea(GdkMonitor *monitor, GdkRectangle *workarea);
void gdk_monitor_get_geometry(GdkMonitor *monitor, GdkRectangle *geometry);
int gdk_monitor_get_width_mm(GdkMonitor *monitor);
int gdk_monitor_get_scale_factor(GdkMonitor *monitor);
GdkMonitor *gdk_display_get_primary_monitor(GdkDisplay *display);
int gtk_widget_get_scale_factor(GtkWidget *widget);
void *gdk_screen_get_rgba_visual(GdkScreen *screen);
gboolean gdk_screen_is_composited(GdkScreen *screen);

// MARK: - Cairo

typedef struct _cairo cairo_t;
typedef struct _cairo_surface cairo_surface_t;
typedef struct _cairo_pattern cairo_pattern_t;

typedef struct {
    double x_bearing;
    double y_bearing;
    double width;
    double height;
    double x_advance;
    double y_advance;
} cairo_text_extents_t;

typedef struct {
    double ascent;
    double descent;
    double height;
    double max_x_advance;
    double max_y_advance;
} cairo_font_extents_t;

cairo_surface_t *cairo_image_surface_create(int format, int width, int height);
cairo_t *cairo_create(cairo_surface_t *target);
void cairo_destroy(cairo_t *cr);
void cairo_surface_destroy(cairo_surface_t *surface);
int cairo_surface_write_to_png(cairo_surface_t *surface, const char *filename);
void cairo_surface_flush(cairo_surface_t *surface);

void cairo_save(cairo_t *cr);
void cairo_restore(cairo_t *cr);
void cairo_translate(cairo_t *cr, double tx, double ty);
void cairo_scale(cairo_t *cr, double sx, double sy);
void cairo_rotate(cairo_t *cr, double angle);

void cairo_set_source_rgb(cairo_t *cr, double red, double green, double blue);
void cairo_set_source_rgba(cairo_t *cr, double red, double green, double blue, double alpha);
void cairo_set_source(cairo_t *cr, cairo_pattern_t *source);
void cairo_set_line_width(cairo_t *cr, double width);
void cairo_set_line_cap(cairo_t *cr, int line_cap);
void cairo_set_line_join(cairo_t *cr, int line_join);
void cairo_set_operator(cairo_t *cr, int op);
void cairo_set_dash(cairo_t *cr, const double *dashes, int num_dashes, double offset);

void cairo_new_path(cairo_t *cr);
void cairo_new_sub_path(cairo_t *cr);
void cairo_close_path(cairo_t *cr);
void cairo_move_to(cairo_t *cr, double x, double y);
void cairo_line_to(cairo_t *cr, double x, double y);
void cairo_curve_to(cairo_t *cr, double x1, double y1, double x2, double y2, double x3, double y3);
void cairo_rectangle(cairo_t *cr, double x, double y, double width, double height);
void cairo_arc(cairo_t *cr, double xc, double yc, double radius, double angle1, double angle2);
void cairo_arc_negative(cairo_t *cr, double xc, double yc, double radius, double angle1, double angle2);

void cairo_fill(cairo_t *cr);
void cairo_fill_preserve(cairo_t *cr);
void cairo_stroke(cairo_t *cr);
void cairo_stroke_preserve(cairo_t *cr);
void cairo_paint(cairo_t *cr);
void cairo_paint_with_alpha(cairo_t *cr, double alpha);
void cairo_push_group(cairo_t *cr);
void cairo_pop_group_to_source(cairo_t *cr);
void cairo_clip(cairo_t *cr);
void cairo_clip_preserve(cairo_t *cr);
void cairo_reset_clip(cairo_t *cr);

cairo_pattern_t *cairo_pattern_create_linear(double x0, double y0, double x1, double y1);
cairo_pattern_t *cairo_pattern_create_radial(
    double cx0, double cy0, double radius0, double cx1, double cy1, double radius1);
void cairo_pattern_add_color_stop_rgba(
    cairo_pattern_t *pattern, double offset, double red, double green, double blue, double alpha);
void cairo_pattern_destroy(cairo_pattern_t *pattern);

typedef struct _cairo_font_options cairo_font_options_t;

cairo_font_options_t *cairo_font_options_create(void);
void cairo_font_options_destroy(cairo_font_options_t *options);
void cairo_font_options_set_antialias(cairo_font_options_t *options, int antialias);
void cairo_font_options_set_hint_style(cairo_font_options_t *options, int hint_style);
void cairo_font_options_set_hint_metrics(cairo_font_options_t *options, int hint_metrics);
void cairo_set_font_options(cairo_t *cr, const cairo_font_options_t *options);

void cairo_select_font_face(cairo_t *cr, const char *family, int slant, int weight);
void cairo_set_font_size(cairo_t *cr, double size);
void cairo_show_text(cairo_t *cr, const char *utf8);
void cairo_text_path(cairo_t *cr, const char *utf8);
void cairo_text_extents(cairo_t *cr, const char *utf8, cairo_text_extents_t *extents);
void cairo_font_extents(cairo_t *cr, cairo_font_extents_t *extents);

// MARK: - GDBus and libdbusmenu, for publishing Ration's own tray item
//
// The tray protocol — org.kde.StatusNotifierItem — has an `Activate` method
// that hosts call when the icon is clicked. libayatana-appindicator never
// published one, so every click had to fall through to the menu. Ration
// publishes the item itself, and keeps libdbusmenu for the menu behind it.

typedef struct _GDBusConnection GDBusConnection;
typedef struct _GDBusNodeInfo GDBusNodeInfo;
typedef struct _GDBusInterfaceInfo GDBusInterfaceInfo;
typedef struct _GDBusMethodInvocation GDBusMethodInvocation;
typedef struct _GCancellable GCancellable;
typedef struct _GVariant GVariant;
typedef struct _GVariantType GVariantType;

// GError, laid out as in glib/gerror.h, so a failed call can be reported.
typedef struct {
    guint domain;
    int code;
    char *message;
} GError;

typedef void (*GDestroyNotify)(gpointer data);

void g_error_free(GError *error);

// G_BUS_TYPE_SESSION is 2.
GDBusConnection *g_bus_get_sync(int bus_type, GCancellable *cancellable, GError **error);
const char *g_dbus_connection_get_unique_name(GDBusConnection *connection);

typedef void (*GBusNameAcquiredCallback)(
    GDBusConnection *connection, const char *name, gpointer user_data);
typedef void (*GBusNameLostCallback)(
    GDBusConnection *connection, const char *name, gpointer user_data);
typedef void (*GBusNameAppearedCallback)(
    GDBusConnection *connection, const char *name, const char *name_owner, gpointer user_data);
typedef void (*GBusNameVanishedCallback)(
    GDBusConnection *connection, const char *name, gpointer user_data);

guint g_bus_own_name_on_connection(
    GDBusConnection *connection, const char *name, int flags,
    GBusNameAcquiredCallback name_acquired_handler, GBusNameLostCallback name_lost_handler,
    gpointer user_data, GDestroyNotify user_data_free_func);

guint g_bus_watch_name_on_connection(
    GDBusConnection *connection, const char *name, int flags,
    GBusNameAppearedCallback name_appeared_handler,
    GBusNameVanishedCallback name_vanished_handler,
    gpointer user_data, GDestroyNotify user_data_free_func);

GDBusNodeInfo *g_dbus_node_info_new_for_xml(const char *xml_data, GError **error);
GDBusInterfaceInfo *g_dbus_node_info_lookup_interface(GDBusNodeInfo *info, const char *name);

typedef void (*GDBusInterfaceMethodCallFunc)(
    GDBusConnection *connection, const char *sender, const char *object_path,
    const char *interface_name, const char *method_name, GVariant *parameters,
    GDBusMethodInvocation *invocation, gpointer user_data);
typedef GVariant *(*GDBusInterfaceGetPropertyFunc)(
    GDBusConnection *connection, const char *sender, const char *object_path,
    const char *interface_name, const char *property_name, GError **error, gpointer user_data);
typedef gboolean (*GDBusInterfaceSetPropertyFunc)(
    GDBusConnection *connection, const char *sender, const char *object_path,
    const char *interface_name, const char *property_name, GVariant *value, GError **error,
    gpointer user_data);

// GDBusInterfaceVTable, laid out as in gio/gdbusconnection.h.
typedef struct {
    GDBusInterfaceMethodCallFunc method_call;
    GDBusInterfaceGetPropertyFunc get_property;
    GDBusInterfaceSetPropertyFunc set_property;
    gpointer padding[8];
} GDBusInterfaceVTable;

guint g_dbus_connection_register_object(
    GDBusConnection *connection, const char *object_path, GDBusInterfaceInfo *interface_info,
    const GDBusInterfaceVTable *vtable, gpointer user_data,
    GDestroyNotify user_data_free_func, GError **error);

gboolean g_dbus_connection_emit_signal(
    GDBusConnection *connection, const char *destination_bus_name, const char *object_path,
    const char *interface_name, const char *signal_name, GVariant *parameters, GError **error);

// The reply is not interesting to Ration, so `callback` is always NULL here.
void g_dbus_connection_call(
    GDBusConnection *connection, const char *bus_name, const char *object_path,
    const char *interface_name, const char *method_name, GVariant *parameters,
    const GVariantType *reply_type, int flags, int timeout_msec, GCancellable *cancellable,
    gpointer callback, gpointer user_data);

GVariant *g_dbus_connection_call_sync(
    GDBusConnection *connection, const char *bus_name, const char *object_path,
    const char *interface_name, const char *method_name, GVariant *parameters,
    const GVariantType *reply_type, int flags, int timeout_msec, GCancellable *cancellable,
    GError **error);

void g_dbus_method_invocation_return_value(
    GDBusMethodInvocation *invocation, GVariant *parameters);

GVariant *g_variant_new_string(const char *string);
GVariant *g_variant_new_object_path(const char *object_path);
GVariant *g_variant_new_boolean(gboolean value);
GVariant *g_variant_new_int32(int value);
GVariant *g_variant_new_tuple(GVariant *const *children, unsigned long n_children);
GVariant *g_variant_get_child_value(GVariant *value, unsigned long index);
gboolean g_variant_get_boolean(GVariant *value);
int g_variant_get_int32(GVariant *value);
const char *g_variant_get_string(GVariant *value, unsigned long *length);
void g_variant_unref(GVariant *value);

typedef struct _GList {
    gpointer data;
    struct _GList *next;
    struct _GList *prev;
} GList;

typedef struct _DbusmenuServer DbusmenuServer;
typedef struct _DbusmenuMenuitem DbusmenuMenuitem;

DbusmenuServer *dbusmenu_server_new(const char *object);
void dbusmenu_server_set_root(DbusmenuServer *self, DbusmenuMenuitem *root);
DbusmenuMenuitem *dbusmenu_server_get_root(DbusmenuServer *self);
DbusmenuMenuitem *dbusmenu_gtk_parse_menu_structure(GtkWidget *widget);
GList *dbusmenu_menuitem_get_children(DbusmenuMenuitem *mi);
gboolean dbusmenu_menuitem_property_set_bool(
    DbusmenuMenuitem *mi, const char *property, gboolean value);

void gtk_menu_popup_at_pointer(GtkWidget *menu, const void *trigger_event);

// MARK: - libayatana-appindicator3

typedef struct _AppIndicator AppIndicator;

AppIndicator *app_indicator_new(const char *id, const char *icon_name, int category);
void app_indicator_set_status(AppIndicator *self, int status);
void app_indicator_set_icon_full(AppIndicator *self, const char *icon_name, const char *icon_desc);
void app_indicator_set_icon_theme_path(AppIndicator *self, const char *icon_theme_path);
void app_indicator_set_attention_icon_full(
    AppIndicator *self, const char *icon_name, const char *icon_desc);
void app_indicator_set_menu(AppIndicator *self, GtkWidget *menu);
void app_indicator_set_label(AppIndicator *self, const char *label, const char *guide);
void app_indicator_set_title(AppIndicator *self, const char *title);
void app_indicator_set_secondary_activate_target(AppIndicator *self, GtkWidget *menuitem);

#ifdef __cplusplus
}
#endif

#endif /* RATION_LINUX_TRAY_H */
