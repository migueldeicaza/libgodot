/**************************************************************************/
/*  rendering_native_surface_apple.mm                                     */
/**************************************************************************/
/*                         This file is part of:                          */
/*                             GODOT ENGINE                               */
/*                        https://godotengine.org                         */
/**************************************************************************/
/* Copyright (c) 2014-present Godot Engine contributors (see AUTHORS.md). */
/* Copyright (c) 2007-2014 Juan Linietsky, Ariel Manzur.                  */
/*                                                                        */
/* Permission is hereby granted, free of charge, to any person obtaining  */
/* a copy of this software and associated documentation files (the        */
/* "Software"), to deal in the Software without restriction, including    */
/* without limitation the rights to use, copy, modify, merge, publish,    */
/* distribute, sublicense, and/or sell copies of the Software, and to     */
/* permit persons to whom the Software is furnished to do so, subject to  */
/* the following conditions:                                              */
/*                                                                        */
/* The above copyright notice and this permission notice shall be         */
/* included in all copies or substantial portions of the Software.        */
/*                                                                        */
/* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,        */
/* EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF     */
/* MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. */
/* IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY   */
/* CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,   */
/* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE      */
/* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                 */
/**************************************************************************/

#include "rendering_native_surface_apple.h"
#include "drivers/apple/rendering_context_driver_vulkan_moltenvk.h"
#include "drivers/gles3/storage/texture_storage.h"
#include "drivers/metal/rendering_context_driver_metal.h"
#include "servers/rendering/gles_context.h"

#if defined(GLES3_ENABLED)
#import <QuartzCore/QuartzCore.h>

#if defined(IOS_ENABLED)
#import <OpenGLES/EAGL.h>
#import <OpenGLES/EAGLDrawable.h>
#import <OpenGLES/ES1/gl.h>
#import <OpenGLES/ES1/glext.h>
#endif

struct WindowData {
	GLint backingWidth;
	GLint backingHeight;
	GLuint viewRenderbuffer, viewFramebuffer;
	GLuint depthRenderbuffer;
#if defined(IOS_ENABLED)
	CAEAGLLayer *layer;
#endif
#if defined(MACOS_ENABLED)
	CAOpenGLLayer *layer;
#endif
};

class GLESContextApple : public GLESContext {
public:
	virtual void initialize() override;
	virtual bool create_framebuffer(DisplayServer::WindowID p_id, Ref<RenderingNativeSurface> p_native_surface) override;
	virtual void resized(DisplayServer::WindowID p_id) override;
	virtual void begin_rendering(DisplayServer::WindowID p_id) override;
	virtual void end_rendering(DisplayServer::WindowID p_id) override;
	virtual bool destroy_framebuffer(DisplayServer::WindowID p_id) override;
	virtual void deinitialize() override;
	virtual uint64_t get_fbo(DisplayServer::WindowID p_id) const override;

protected:
	bool create_framebuffer(DisplayServer::WindowID p_id, void *p_layer);

private:
	HashMap<DisplayServer::WindowID, WindowData> windows;
#if defined(IOS_ENABLED)
	EAGLContext *context = nullptr;
#endif
};

void GLESContextApple::initialize() {
#if defined(IOS_ENABLED)
	// Create GL ES 3 context
	if (OS::get_singleton()->get_current_rendering_method() == "gl_compatibility" && context == nullptr) {
		context = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES3];
		NSLog(@"Setting up an OpenGL ES 3.0 context.");
		if (!context) {
			NSLog(@"Failed to create OpenGL ES 3.0 context!");
			return;
		}
	}

	if (![EAGLContext setCurrentContext:context]) {
		NSLog(@"Failed to set EAGLContext!");
		return;
	}
#endif
}

void GLESContextApple::resized(DisplayServer::WindowID p_id) {
	ERR_FAIL_COND(!windows.has(p_id));
	WindowData &gles_data = windows[p_id];
#if defined(IOS_ENABLED)
	[EAGLContext setCurrentContext:context];
	CAEAGLLayer *layer = gles_data.layer;
	destroy_framebuffer(p_id);
	create_framebuffer(p_id, (__bridge void *)layer);
#endif
}

void GLESContextApple::begin_rendering(DisplayServer::WindowID p_id) {
	ERR_FAIL_COND(!windows.has(p_id));
	WindowData &gles_data = windows[p_id];
#if defined(IOS_ENABLED)
	[EAGLContext setCurrentContext:context];
	glBindFramebufferOES(GL_FRAMEBUFFER_OES, gles_data.viewFramebuffer);
#endif
}

void GLESContextApple::end_rendering(DisplayServer::WindowID p_id) {
	ERR_FAIL_COND(!windows.has(p_id));
	WindowData &gles_data = windows[p_id];
#if defined(IOS_ENABLED)
	[EAGLContext setCurrentContext:context];
	glBindRenderbufferOES(GL_RENDERBUFFER_OES, gles_data.viewRenderbuffer);
	[context presentRenderbuffer:GL_RENDERBUFFER_OES];

#ifdef DEBUG_ENABLED
	GLenum err = glGetError();
	if (err) {
		NSLog(@"DrawView: %x error", err);
	}
#endif
#endif
}

void GLESContextApple::deinitialize() {
#if defined(IOS_ENABLED)
	if ([EAGLContext currentContext] == context) {
		[EAGLContext setCurrentContext:nil];
	}

	if (context) {
		context = nil;
	}
#endif
}

bool GLESContextApple::create_framebuffer(DisplayServer::WindowID p_id, Ref<RenderingNativeSurface> p_native_surface) {
#if defined(IOS_ENABLED)
	CAEAGLLayer *layer = nullptr;
	Ref<RenderingNativeSurfaceApple> apple_surface = Object::cast_to<RenderingNativeSurfaceApple>(*p_native_surface);
	if (apple_surface.is_valid()) {
		layer = (__bridge CAEAGLLayer *)apple_surface->get_layer();
	}
	if (layer == nullptr) {
		return false;
	}
	return create_framebuffer(p_id, (__bridge void *)layer);
#else
	return false;
#endif
}

bool GLESContextApple::create_framebuffer(DisplayServer::WindowID p_id, void *p_layer) {
	WindowData &gles_data = windows[p_id];
#if defined(IOS_ENABLED)
	[EAGLContext setCurrentContext:context];
	gles_data.layer = (__bridge CAEAGLLayer *)p_layer;

	glGenFramebuffersOES(1, &gles_data.viewFramebuffer);
	glGenRenderbuffersOES(1, &gles_data.viewRenderbuffer);

	glBindFramebufferOES(GL_FRAMEBUFFER_OES, gles_data.viewFramebuffer);
	glBindRenderbufferOES(GL_RENDERBUFFER_OES, gles_data.viewRenderbuffer);
	// This call associates the storage for the current render buffer with the EAGLDrawable (our CAself)
	// allowing us to draw into a buffer that will later be rendered to screen wherever the layer is (which corresponds with our view).
	[context renderbufferStorage:GL_RENDERBUFFER_OES fromDrawable:gles_data.layer];
	glFramebufferRenderbufferOES(GL_FRAMEBUFFER_OES, GL_COLOR_ATTACHMENT0_OES, GL_RENDERBUFFER_OES, gles_data.viewRenderbuffer);

	glGetRenderbufferParameterivOES(GL_RENDERBUFFER_OES, GL_RENDERBUFFER_WIDTH_OES, &gles_data.backingWidth);
	glGetRenderbufferParameterivOES(GL_RENDERBUFFER_OES, GL_RENDERBUFFER_HEIGHT_OES, &gles_data.backingHeight);

	// For this sample, we also need a depth buffer, so we'll create and attach one via another renderbuffer.
	glGenRenderbuffersOES(1, &gles_data.depthRenderbuffer);
	glBindRenderbufferOES(GL_RENDERBUFFER_OES, gles_data.depthRenderbuffer);
	glRenderbufferStorageOES(GL_RENDERBUFFER_OES, GL_DEPTH_COMPONENT16_OES, gles_data.backingWidth, gles_data.backingHeight);
	glFramebufferRenderbufferOES(GL_FRAMEBUFFER_OES, GL_DEPTH_ATTACHMENT_OES, GL_RENDERBUFFER_OES, gles_data.depthRenderbuffer);

	if (glCheckFramebufferStatusOES(GL_FRAMEBUFFER_OES) != GL_FRAMEBUFFER_COMPLETE_OES) {
		NSLog(@"failed to make complete framebuffer object %x", glCheckFramebufferStatusOES(GL_FRAMEBUFFER_OES));
		return false;
	}

	return true;
#else
	return false;
#endif
}

// Clean up any buffers we have allocated.
bool GLESContextApple::destroy_framebuffer(DisplayServer::WindowID p_id) {
	ERR_FAIL_COND_V(!windows.has(p_id), false);
	WindowData &gles_data = windows[p_id];
#if defined(IOS_ENABLED)
	[EAGLContext setCurrentContext:context];
	glDeleteFramebuffersOES(1, &gles_data.viewFramebuffer);
	gles_data.viewFramebuffer = 0;
	glDeleteRenderbuffersOES(1, &gles_data.viewRenderbuffer);
	gles_data.viewRenderbuffer = 0;

	if (gles_data.depthRenderbuffer) {
		glDeleteRenderbuffersOES(1, &gles_data.depthRenderbuffer);
		gles_data.depthRenderbuffer = 0;
	}

	windows.erase(p_id);
	return true;
#else
	windows.erase(p_id);
	return false;
#endif
}

uint64_t GLESContextApple::get_fbo(DisplayServer::WindowID p_id) const {
	ERR_FAIL_COND_V(!windows.has(p_id), 0);
	const WindowData &gles_data = windows[p_id];
	return gles_data.viewFramebuffer;
}

#endif // GLES3_ENABLED

void RenderingNativeSurfaceApple::_bind_methods() {
	ClassDB::bind_static_method("RenderingNativeSurfaceApple", D_METHOD("create", "layer"), &RenderingNativeSurfaceApple::create_api);
}

Ref<RenderingNativeSurfaceApple> RenderingNativeSurfaceApple::create_api(/* GDExtensionConstPtr<const void> */ uint64_t p_layer) {
	return RenderingNativeSurfaceApple::create((void *)p_layer /* .operator const void *() */);
}

Ref<RenderingNativeSurfaceApple> RenderingNativeSurfaceApple::create(void *p_layer) {
	Ref<RenderingNativeSurfaceApple> result = memnew(RenderingNativeSurfaceApple);
	result->layer = p_layer;
	return result;
}

RenderingContextDriver *RenderingNativeSurfaceApple::create_rendering_context(const String &p_rendering_driver) {
#if defined(VULKAN_ENABLED)
	if (p_rendering_driver == "vulkan") {
		return memnew(RenderingContextDriverVulkanMoltenVk);
	}
#endif
#if defined(METAL_ENABLED)
	if (p_rendering_driver == "metal") {
		if (@available(ios 14.0, *)) {
			return memnew(RenderingContextDriverMetal);
		}
	}
#endif
	return nullptr;
}

GLESContext *RenderingNativeSurfaceApple::create_gles_context() {
#if defined(GLES3_ENABLED)
	return memnew(GLESContextApple);
#else
	return nullptr;
#endif
}

RenderingNativeSurfaceApple::RenderingNativeSurfaceApple() {
}

RenderingNativeSurfaceApple::~RenderingNativeSurfaceApple() {
}
