import type { FastifyReply, FastifyRequest } from "fastify";
import { ZodError } from "zod";

export class AppError extends Error {
  constructor(public readonly code: string, message: string, public readonly statusCode = 400) { super(message); }
}

export function errorHandler(error: Error, request: FastifyRequest, reply: FastifyReply) {
  if (error instanceof ZodError) {
    return reply.status(400).send({ error: { code: "VALIDATION_ERROR", message: "The request is invalid", requestId: request.id } });
  }
  if (error instanceof AppError) {
    return reply.status(error.statusCode).send({ error: { code: error.code, message: error.message, requestId: request.id } });
  }
  request.log.error({ err: error, operation: "request.failed" }, "Request failed");
  return reply.status(500).send({ error: { code: "INTERNAL_ERROR", message: "An unexpected error occurred", requestId: request.id } });
}
